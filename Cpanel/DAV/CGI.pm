
# cpanel - Cpanel/DAV/CGI.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DAV::CGI;

use strict;
use warnings;

use HTTP::Response ();
use XML::Simple    ();

use Cpanel::DAV::Tmpdir         ();
use Cpanel::SafeRun::InOut      ();
use Cpanel::DAV::CGI::LogRotate ();
use Cpanel::PwCache             ();

# Do not add items @INC.
# Do not use Cpanel::Locale.
# Do not lazy load Cpanel::Locale, even via Cpanel::Locale::Lazy.
# All messages in this module are untranslated.

our $DEBUG = 0;

=head1 NAME

Cpanel::DAV::CGI

=head1 FUNCTIONS

=head2 run_cgi_application()

Helper for running a CGI application from cpdavd

=head3 Arguments

This function accepts two arguments:

=over

=item * The name of the CGI application to be run. As of this writing, the
supported applications include:

  z-push
  autodiscover

=item * The HTTP::Request object for the request.

=back

=head2 Returns

This function returns an HTTP::Response object ready to send back to the client.

=cut

my %apps;

sub _init {
    require Cpanel::Binaries;
    my $php_dir = Cpanel::Binaries::get_php_3rdparty_dir();
    %apps = (
        'z-push' => {
            precheck => sub {

                # Cannot use anything here that lazy-loads modules
                my $quota_check_file = sprintf( '%s/.z-push.write', Cpanel::PwCache::gethomedir() );
                my $ok               = eval {
                    open my $fh, '>', $quota_check_file or return;
                    print {$fh} "\n" or return;
                    close $fh        or return;
                    1;
                };
                unlink $quota_check_file;

                if ( !$ok ) {
                    return HTTP::Response->new( 507, 'Insufficient Storage', undef, undef );
                }
                return;
            },
            command => [
                '/usr/local/cpanel/3rdparty/bin/php-cgi',
                '-d',
                'memory_limit=384M',    # needed for processing larger email attachments
                '/usr/local/cpanel/3rdparty/usr/share/z-push/src/index.php',
            ],
            response_builder => \&_generic_response_builder,
            logrotate        => {
                basedir_relative => '.z-push/log',
                log_pattern      => '*.log',
                min_size_k       => 512,
                max_size_k       => 10240,
            },
        },
        'autodiscover' => {
            command => [
                '/usr/local/cpanel/3rdparty/bin/php-cgi',
                '/usr/local/cpanel/3rdparty/usr/share/z-push/src/autodiscover/autodiscover.php',
            ],
            response_builder => \&_generic_response_builder,
        },
    );
    return;
}

# split out into a separate subroutine so Devel::Cover has awareness of it
sub _generic_response_builder {
    my ($data) = @_;
    $data = ''                     if !$data;
    $data = "Status: 200\r\n$data" if $data !~ /\AStatus:/;
    my $response = HTTP::Response->parse($data);
    return $response;
}

sub run_cgi_application {
    my ( $app, $httprequest ) = @_;

    _init();

    if ($DEBUG) {
        eval 'require Data::Dumper; warn Data::Dumper::Dumper($httprequest);';    ## no critic qw(ProhibitStringyEval)
    }

    # Need this to prevent temp files from being written (unsafely) to /tmp
    $ENV{TMPDIR} = Cpanel::DAV::Tmpdir::for_current_user();

    my $appinfo  = $apps{$app} || die sprintf( "The system could not identify the “%s” app.", $app );

    # URI rewriting
    if ( $appinfo->{rewrite} ) {
        $appinfo->{rewrite}->($httprequest);
        $ENV{REQUEST_URI} = $httprequest->uri;                                    # update environment to match new URI
    }

    my $response;

    # If this app has a 'handler', that means there is a single function that
    # accepts an HTTP::Request object as its input and gives an HTTP::Response
    # object as its output without launching any child process.
    if ( $appinfo->{handler} ) {
        $response = $appinfo->{handler}->($httprequest);
    }
    elsif ( $appinfo->{precheck} && defined( my $precheck_response = $appinfo->{precheck}->() ) ) {
        $response = $precheck_response;
    }

    # Otherwise, it should have a 'command' and 'response_builder', because it's a
    # regular CGI application that launches a child and gathers the response from the
    # stdout of that process.
    else {

        my $content = _run_request(
            $app, $appinfo,
            sub {
                # Setup child environment:

                # Environment variables are mostly already set (globally) by the Cpanel::Httpd object
                # Exception: SCRIPT_FILENAME needs to be set here because this is where we know (sort of)
                # which file is being executed.
                $ENV{SCRIPT_URL}           = '/';
                $ENV{SCRIPT_FILENAME}      = $appinfo->{command}[-1];
                $ENV{REDIRECT_STATUS}      = 1;                         # same thing cpsrvd does, but often set to 200
                $ENV{HTTP_ACCEPT_ENCODING} = '';                        # Force Sabre to always send back unencode since we do this in cpdavd

                for my $h (
                    [qw(HTTP_DESTINATION          Destination)],        # Needed for MOVE requests
                    [qw(HTTP_BRIEF                Brief)],
                    [qw(HTTP_DEPTH                Depth)],              # Needed by various vCard REPORT calls
                    [qw(HTTP_IF_MATCH             If-Match)],           # Needed by various vCard REPORT calls
                ) {
                    my ( $env_name, $header_name ) = @$h;
                    my $header_value = $httprequest->header($header_name);
                    $ENV{$env_name} = $header_value if defined $header_value;
                }
            },
            sub {
                # From parent process send request to child process
                _write_to_child( shift, $httprequest, $app );
            },
            sub {
                # From parent process fetch the content from the child process
                return _read_from_child( shift, $app );
            }
        );

        # Build the response from the raw data
        $response = $appinfo->{response_builder}->($content);
    }

    if ($DEBUG) {
        eval 'require Data::Dumper; warn Data::Dumper::Dumper($response);';    ## no critic qw(ProhibitStringyEval)
    }

    if ( $appinfo->{logrotate} ) {
        eval {
            my $lr = Cpanel::DAV::CGI::LogRotate->new( %{ $appinfo->{logrotate} } );
            $lr->run;
        };
        if ( my $exception = $@ ) {
            print STDERR $exception;
        }
    }

    return $response;
}

# Set the required environment variables that normally would have been set by Cpanel::Httpd
sub run_cgi_application_directly {
    my ( $app, $httprequest, $user ) = @_;

    local $ENV{REMOTE_USER}    = $user;
    local $ENV{REQUEST_METHOD} = $httprequest->method;
    local $ENV{REQUEST_URI}    = $httprequest->uri;
    local $ENV{CONTENT_TYPE}   = $httprequest->header('Content-Type');
    local $ENV{CONTENT_LENGTH} = length( $httprequest->content );

    return run_cgi_application( $app, $httprequest );
}

sub _write_to_child {

    # From parent process send request to child process
    my ( $writeh, $httprequest ) = @_;

    my $request_body = $httprequest->content;

    # Cpanel::Httpd sometimes sets the content field of the HTTP::Request object
    # to a code ref, which doesn't read the request body until you execute it and
    # allows you to pipe it directly to another file handle so that you don't have
    # to buffer it in memory (useful for larger requests).
    if ( 'CODE' eq ref $request_body ) {
        $request_body->($writeh);
    }

    # But sometimes it's still just a string, in which case we just to write it to the pipe.
    elsif ( length $request_body ) {
        print {$writeh} $request_body;
    }
    return;
}

sub _read_from_child {

    # From parent process fetch the content from the child process
    my ( $readh, $app ) = @_;
    my $content;
    {
        local $/;
        $content = readline($readh);
        if ( !$content ) {
            close($readh);
            die sprintf( "The system failed to fetch the response data for “%s”.", $app );
        }
    }
    return $content;
}

# so that it's mockable in unit tests
sub _run_request {
    my ( $app, $appinfo, $pre, $send, $done ) = @_;

    my $writeh = Symbol::gensym();
    my $readh  = Symbol::gensym();

    # Fork the child process
    my $pid = Cpanel::SafeRun::InOut::inout( $writeh, $readh, $pre, @{ $appinfo->{command} } );
    if ( !$pid ) {
        die sprintf( "The system was unable to run the command “%s” while forking.", $app );
    }

    # Write data to child app
    $send->($writeh);

    # Let the child know we are done writing
    close($writeh) || die "The system was unable to close the file handle.";

    # Read data from child app
    my $content = $done->($readh);

    # Let the child know we are done reading so it exits
    #TODO - There are times when the read handle is already closed, so closing it a second time results in a die.
    # close($readh) || die "The system detected that the file is already closed.";

    return $content;
}

1;
