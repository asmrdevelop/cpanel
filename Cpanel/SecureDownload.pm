package Cpanel::SecureDownload;

# cpanel - Cpanel/SecureDownload.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SecureDownload -- Download content from a URL

=head1 SYNOPSIS

 use Cpanel::SecureDownload ();

 my ($success, $errmsg_or_content) = Cpanel::SecureDownloads::fetch_url(
     "https://mirror.secteamsix.dev.cpanel.net/gpgkeys/test-01.pub.key"
 );

 if (!$success) {
     print "Failure to download: $msg\n";
 }

=head1 DESCRIPTION

 This module is meant to replace the use of wget in
 Cpanel::Crypt::GPG::VendorKeys as well as in scripts/fix-cpanel-perl.
 It attempt to download the file using the following methods, in order:
 Cpanel::HTTP::Client, curl, and finally wget.  Each mething will attempt
 to use Mozilla::CA, if available, as its source for certificate
 authorities.
 Both Cpanel::Crypt::GPG::VendorKeys and scripts/fix-cpanel-perl passed
 different options to wget.  This module allows for a set of equivalent
 options to be passed in and, where supported, will attempt set those
 for Cpanel::HTTP::Client and curl.  And if wget is invoked, the
 appropriate options will be set as before.

=head1 METHODS

=cut

use strict;
use warnings;

# Do not include any external modules here
# This module may be called from system perl and may not be able to load them

=head2 fetch_url( $url, %opts )

=over 2

Downloads content

$url The URL from which to download content

%opts can contain:

=over 4

=item * output-file

Download the content to the specified file rather than returning it

=item * no-check-certificate

For testing, disable the certificate check (allow self-signed, etc.)
Cpanel::HTTP::Client - not relevant, to disable certificate
checking in Cpanel::HTTP::Client, create the touchfile:
/var/cpanel/no_verify_SSL
curl, wget:  both have options for this

=item * not-verbose

Set not verbose, only relevant for wget

=item * tries

Number of attempts to make before declaring failure
curl, wget only

=item * retry-delay

How long to wait between retries
curl, wget only

=item * timeout

How long to wait before declaring failure
Cpanel::HTTP::Client, curl, & wget all support

=item * dns-timeout

wget only, timeout for dns resolution

=item * read-timeout

wget only, timeout for read operation

=item * no-dns-cache

wget only, turn off caching of DNS lookups.

=item * retry-connrefused

wget only, consider "connection refused" a transient error and try again.

=back

Returns a list containing ($success, $message_or_content).

If it succeeds the second item will only return the downloaded
content if an output file was not specified by the "output-file" option.

=back

=cut

sub fetch_url {
    my ( $url, %opts ) = @_;

    my @methods = (
        [ 'Cpanel::HTTP::Client' => \&_try_with_http_client ],
        [ 'curl'                 => \&_try_with_curl ],
        [ 'wget'                 => \&_try_with_wget ]
    );

    my $all_errors;

    foreach my $method (@methods) {
        my ( $name, $sub ) = @{$method};

        local $@;
        my $contents = eval { $sub->( $url, %opts ); };
        return ( 1, $contents ) if !$@;

        my $error = "Failed to fetch using $name: $@";
        $all_errors .= $error . "\n";
    }

    return ( 0, $all_errors );
}

=head2 _try_with_http_client() (private)

=over 2

Attempts content download via Cpanel::HTTP::Client

=back

=cut

sub _try_with_http_client {
    my ( $url, %opts ) = @_;

    # Dependencies of Cpanel::HTTP::Client are not always available
    # during installation. Give up early if that is the case.
    die "Cpanel::HTTP::Client unavailable during initial install" if $ENV{'CPANEL_BASE_INSTALL'};

    require Cpanel::HTTP::Client;

    my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
    $http->timeout( $opts{'timeout'} ) if exists $opts{'timeout'};

    my $content = $http->get($url)->content();

    return $content unless exists $opts{'output-file'};

    my $temp_file = $opts{'output-file'} . '.' . time . '.temp';

    open my $fh, '>', $temp_file
      or die "Unable to open $temp_file: $!";
    print {$fh} $content;
    close $fh;

    unlink $opts{'output-file'} if -e $opts{'output-file'};
    rename $temp_file, $opts{'output-file'};

    return 1;
}

=head2 _try_with_curl() (private)

=over 2

Attempts content download via curl

=back

=cut

sub _try_with_curl {
    my ( $url, %opts ) = @_;

    my $curl_bin = _find_curl_bin();
    die "Unable to find curl" unless $curl_bin;

    my @cmd_args = _build_curl_cmd_line( $url, %opts );

    return _execute_download_tool( $curl_bin, @cmd_args );
}

=head2 _try_with_wget() (private)

=over 2

Attempts content download via wget

=back

=cut

sub _try_with_wget {
    my ( $url, %opts ) = @_;

    my $wget_bin = _find_wget_bin();
    die "Unable to find wget" unless $wget_bin;

    my @cmd_args = _build_wget_cmd_line( $url, %opts );

    return _execute_download_tool( $wget_bin, @cmd_args );
}

=head2 _get_mozilla_ca_file() (private)

=over 2

Returns path to the Mozilla::CA ca file

=back

=cut

sub _get_mozilla_ca_file {

    my $ca_file = eval {
        require    # Cpanel::Static OK - inside an eval
          Mozilla::CA;
        Mozilla::CA::SSL_ca_file();
    };
    return if $@;
    return unless -e $ca_file;
    return $ca_file;
}

=head2 _find_curl_bin() (private)

=over 2

Finds location of installed curl binary.

=back

=cut

sub _find_curl_bin {

    for my $bin (qw(/usr/bin/curl /bin/curl /usr/local/bin/curl)) {
        next if ( !-e $bin );
        next if ( !-x _ );
        next if ( -z _ );
        return $bin;
    }

    return undef;
}

=head2 _find_wget_bin() (private)

=over 2

Finds location of installed wget binary.

=back

=cut

sub _find_wget_bin {

    for my $bin (qw(/usr/bin/wget /bin/wget /usr/local/bin/wget)) {
        next if ( !-e $bin );
        next if ( !-x _ );
        next if ( -z _ );
        return $bin;
    }

    return undef;
}

=head2 _build_curl_cmd_line() (private)

=over 2

Constructs list of command line arguments for curl based
on the options hash.

Returns list of command line arguments to pass to curl

=back

=cut

sub _build_curl_cmd_line {
    my ( $url, %opts ) = @_;

    my @cmd_args;

    if ( exists $opts{'tries'} ) {
        push @cmd_args, '--retry';
        push @cmd_args, $opts{'tries'};
    }

    if ( exists $opts{'retry-delay'} ) {
        push @cmd_args, '--retry-delay';
        push @cmd_args, $opts{'retry-delay'};
    }

    if ( exists $opts{'timeout'} ) {
        push @cmd_args, '--max-time';
        push @cmd_args, $opts{'timeout'};
    }

    if ( exists $opts{'no-check-certificate'} && $opts{'no-check-certificate'} ) {
        push @cmd_args, '-k';
    }
    else {
        my $ca_file = _get_mozilla_ca_file();
        if ($ca_file) {
            push @cmd_args, "--cacert";
            push @cmd_args, $ca_file;
        }
    }

    push @cmd_args, '--silent';
    push @cmd_args, '-o';
    push @cmd_args, exists $opts{'output-file'} ? $opts{'output-file'} : '-';
    push @cmd_args, $url;

    return @cmd_args;
}

=head2 _build_wget_cmd_line() (private)

=over 2

Constructs list of command line arguments for wget based
on the options hash.

Returns list of command line arguments to pass to wget

=back

=cut

sub _build_wget_cmd_line {
    my ( $url, %opts ) = @_;

    my @cmd_args;

    push @cmd_args, '-nv'                                     if exists $opts{'not-verbose'};
    push @cmd_args, '--no-dns-cache'                          if exists $opts{'no-dns-cache'};
    push @cmd_args, '--tries=' . $opts{'tries'}               if exists $opts{'tries'};
    push @cmd_args, '--timeout=' . $opts{'timeout'}           if exists $opts{'timeout'};
    push @cmd_args, '--dns-timeout=' . $opts{'dns-timeout'}   if exists $opts{'dns-timeout'};
    push @cmd_args, '--read-timeout=' . $opts{'read-timeout'} if exists $opts{'read-timeout'};
    push @cmd_args, '--waitretry=' . $opts{'retry-delay'}     if exists $opts{'retry-delay'};
    push @cmd_args, '--retry-connrefused'                     if exists $opts{'retry-connrefused'};

    if ( exists $opts{'no-check-certificate'} && $opts{'no-check-certificate'} ) {
        push @cmd_args, '--no-check-certificate';
    }
    else {
        my $ca_file = _get_mozilla_ca_file();
        if ($ca_file) {
            push @cmd_args, "--ca-certificate=$ca_file";
        }
    }

    push @cmd_args, '-O';
    push @cmd_args, exists $opts{'output-file'} ? $opts{'output-file'} : '-';
    push @cmd_args, $url;

    return @cmd_args;
}

=head2 _execute_download_tool() (private)

=over 2

Execute the tool (curl or wget) which downloads
the content

Returns The stdio from the download tool.
This will contain the content if an output file
has not been specified

=back

=cut

sub _execute_download_tool {
    my ( $bin, @cmd_args ) = @_;

    if ( _try_load_saferun_object() ) {
        return _run_with_saferun_object( $bin, @cmd_args );
    }
    elsif ( _try_load_ipc_open3() ) {
        return _run_with_ipc_open3( $bin, @cmd_args );
    }
    else {
        die "Unable to find a suitable method to fetch the URL\n";
    }

    return;
}

=head2 _try_load_saferun_object() (private)

=over 2

Attempt to load Cpanel::SafeRun::Object

return true/false upon success/failure

=back

=cut

sub _try_load_saferun_object {
    eval { require Cpanel::SafeRun::Object; };
    return $@ ? 0 : 1;
}

=head2 _try_load_ipc_open3() (private)

=over 2

Attempt to load IPC::Open3

return true/false upon success/failure

=back

=cut

sub _try_load_ipc_open3 {
    eval { require IPC::Open3; };
    return $@ ? 0 : 1;
}

=head2 _run_with_saferun_object() (private)

=over 2

Execute the download program via Cpanel::SafeRun::Object

=back

=cut

sub _run_with_saferun_object {
    my ( $bin, @cmd_args ) = @_;

    my $run = Cpanel::SafeRun::Object->new(
        program => $bin,
        args    => \@cmd_args,
    );

    if ( !$run ) {
        die "Failed to invoke $bin binary.";
    }

    my $rc = $run->CHILD_ERROR() >> 8;

    if ( $rc != 0 ) {
        my $full_command = $bin . ' ' . join ' ', @cmd_args;
        my $stderr       = "Error encountered while running $full_command command: " . $run->stderr();
        die $stderr;
    }

    my $stdout = $run->stdout();

    return $stdout;
}

=head2 _run_with_ipc_open3() (private)

=over 2

Execute the download program via IPC::Open3

Done as a fallback if we cannot load Cpanel::SafeRun::Object

=back

=cut

sub _run_with_ipc_open3 {
    my ( $bin, @cmd_args ) = @_;

    my ( $out_fh, $err_fh );
    my $pid = IPC::Open3::open3( undef, $out_fh, $err_fh, $bin, @cmd_args );

    waitpid( $pid, 0 );

    if ($?) {
        my $full_command = $bin . ' ' . join ' ', @cmd_args;
        my $stderr       = "Error encountered while running $full_command command: ";
        while ( my $line = <$err_fh> ) {
            $stderr .= $line;
        }
        die $stderr;
    }

    my $stdout;
    while ( my $line = <$out_fh> ) {
        $stdout .= $line;
    }

    return $stdout;
}

1;
