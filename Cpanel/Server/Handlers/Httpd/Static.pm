package Cpanel::Server::Handlers::Httpd::Static;

# cpanel - Cpanel/Server/Handlers/Httpd/Static.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::Static

=head1 SYNOPSIS

    # For a static file:
    Cpanel::Server::Handlers::Httpd::CGI::handle( %OPTS );

    # For a directory index:
    Cpanel::Server::Handlers::Httpd::CGI::handle_directory( %OPTS );

=head1 DESCRIPTION

This is cphttpd’s handler for serving static files.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile::ReadFast                   ();
use Cpanel::Exception                            ();
use Cpanel::Server::Constants                    ();
use Cpanel::Server::Handlers::Httpd::ContentType ();

use constant {
    _ENOENT => 2,
    _EISDIR => 21,

    _DEFAULT_CONTENT_TYPE => 'application/octet-stream',
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 handle( %OPTS )

This serves up a static file.

%OPTS are:

=over

=item * C<server_obj> - An instance of L<Cpanel::Server>.

=item * C<setuid> - The name of the user that the file will be loaded as.

=item * C<path> - The filesystem path of the file to load.

=item * C<size_limit> - Optional; if given, and if the file’s size exceeds
this number of bytes, a L<Cpanel::Exception::cpsrvd::InternalError> is thrown
with a message about the file size excess.

=item * C<headers> - Optional; array reference of key/value pairs that
correspond to HTTP headers that will be included in the response. See below
about the C<Content-Type> header.

=back

B<NOTE:> This does B<not> accept C<path>s with trailing slashes.
If you want to mimic Apache httpd’s
L<DirectoryIndex|https://httpd.apache.org/docs/current/mod/mod_dir.html#directoryindex>,
directive, then use C<handle_directory()>.

If no C<Content-Type> header is given, this will try to detect a MIME
type automatically. See L<Cpanel::Server::Handlers::Httpd::ContentType>
for the specific logic used.

=cut

sub handle {
    my (@opts_kv) = @_;

    return _handle_path_if_exists(@opts_kv) || _die_404();
}

=head2 handle_directory( %OPTS )

Similar to C<handle()> but also requires the following:

=over

=item * C<dirindex> - Array reference, analogous to Apache httpd’s
L<DirectoryIndex|https://httpd.apache.org/docs/current/mod/mod_dir.html#directoryindex>,
this is a list of filenames to attempt to load, in order of priority.
For example, to mimic Apache httpd’s default (as of v2.4), give
C<['index.html']>.

=back

This function also requires that C<path> end with a forward-slash (C</>).

=cut

sub handle_directory {
    my (%opts) = @_;

    rindex( $opts{'path'}, '/' ) == ( length( $opts{'path'} ) - 1 ) or do {
        die "“path” ($opts{'path'}) must end with a “/”!";    #implementor error
    };

    my @indexes = @{ $opts{'dirindex'} };

    while ( my $file = shift @indexes ) {
        return if _handle_path_if_exists(
            %opts,
            path => "$opts{'path'}$file",
        );
    }

    _die_404();

    return;
}

# Returns 1 and serves up the file if all is well;
# returns undef if the “path” is well-formed but just doesn’t exist.
# Any other failure prompts an appropriate exception.
sub _handle_path_if_exists {
    my (%opts) = @_;

    die 'Need setuid!' if !$opts{'setuid'};

    # We throw 404 here rather than returning undef because these
    # are integrity checks of the “path”, and if they fail then there’s
    # no context where there’s a valid payload for the request.

    # A sanity-check backup to logic in the main Httpd.pm.
    _die_404() if -1 != index $opts{'path'}, '..';
    _die_404() if -1 != index $opts{'path'}, "\0";

    # 404 on trailing slash because if the caller meant to accommodate
    # trailing slash, they would call handle_directory() instead.
    _die_404() if '/' eq substr( $opts{'path'}, -1 );

    my $server_obj = $opts{'server_obj'};
    $server_obj->switchuser_or_reset_connection( $opts{'setuid'} );

    # We could turn EACCES into HTTP 403, but for now let’s just
    # let that propagate as a 500. Based on the need that cphttpd fulfills,
    # we can legitimately consider EACCES as a server misconfiguration.

    open my $rfh, '<', $opts{'path'} or do {
        return undef if $! == _ENOENT();

        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $opts{'path'}, error => $!, mode => '<' ] );
    };

    if ( $opts{'size_limit'} ) {
        require Cpanel::Autodie;
        Cpanel::Autodie::stat($rfh);

        if ( ( -s _ ) > $opts{'size_limit'} ) {
            die Cpanel::Exception::create( 'cpsrvd::InternalServerError', 'The requested resource exceeds this server’s payload size limit.' );
        }
    }

    my $content = q<>;

    local $@;
    my $ok = eval {
        Cpanel::LoadFile::ReadFast::read_all_fast( $rfh, $content );
        1;
    };

    if ( !$ok ) {
        my $err = $@;

        _die_404() if $! == _EISDIR();

        local $@ = $err;
        die;
    }

    my $headers_ar = _determine_headers( \$content, \%opts );

    $server_obj->connection()->write_buffer(
        $server_obj->fetchheaders(
            $Cpanel::Server::Constants::FETCHHEADERS_STATIC_CONTENT,
            $Cpanel::Server::Constants::HTTP_STATUS_OK,
            $Cpanel::Server::Constants::FETCHHEADERS_LOGACCESS,
          )
          . join( "\r\n", @$headers_ar ) . "\r\n"
          . $server_obj->nocache() . "\r\n"
          . $content
    );

    return 1;
}

sub _determine_headers {
    my ( $content_sr, $opts_hr ) = @_;

    my @headers = (
        'Content-length: ' . length($$content_sr),
    );

    my $gave_content_type_header;

    if ( $opts_hr->{'headers'} ) {
        while ( @{ $opts_hr->{'headers'} } ) {
            my ( $h, $v ) = splice( @{ $opts_hr->{'headers'} }, 0, 2 );
            push @headers, "$h: $v";

            if ( ( $h =~ tr<A-Z><a-z>r ) eq 'content-type' ) {
                $gave_content_type_header = 1;
            }
        }
    }

    if ( !$gave_content_type_header ) {
        my $type = Cpanel::Server::Handlers::Httpd::ContentType::detect( $content_sr, $opts_hr->{'path'} );
        $type ||= _DEFAULT_CONTENT_TYPE;

        push @headers, "Content-Type: $type";
    }

    return \@headers;
}

sub _die_404 {
    die Cpanel::Exception::create('cpsrvd::NotFound');
}

1;
