package Cpanel::SSH::Key;

# cpanel - Cpanel/SSH/Key.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception            ();
use Cpanel::SafeRun::Object      ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::Config::LoadCpConf   ();

my $VALIDATE_BIN     = '/usr/local/cpanel/scripts/validate_sshkey_passphrase';
my $VALIDATE_TIMEOUT = 6;

=head1 NAME

Cpanel::SSH::Key

=head1 DESCRIPTION

Provides a set of key-related SSH configurations, utilities, and functions.

=head1 FUNCTIONS

=cut

sub validate_key_passphrase {
    my ( $path, $passphrase ) = @_;

    my $run = Cpanel::SafeRun::Object->new(
        program => $VALIDATE_BIN,
        args    => [$path],
        stdin   => $passphrase,
        timeout => $VALIDATE_TIMEOUT,
    );

    if ( $run->timed_out() ) {
        die Cpanel::Exception::create( 'Timeout', 'The call to “[_1]” timed out after [quant,_2,second,seconds].', [ $VALIDATE_BIN, $VALIDATE_TIMEOUT ] );
    }

    $run->die_if_error();

    my $output = $run->stdout();

    my $response_hr = Cpanel::AdminBin::Serializer::Load($output);

    #If we died from an exception, it'll be recorded here.
    if ( !$response_hr->{'status'} ) {
        my $class = $response_hr->{'class'};
        if ( length $class ) {
            $class =~ s<\ACpanel::Exception::><>;
        }
        else {
            $class = 'Cpanel::Exception';
        }

        die Cpanel::Exception::create_raw( $class, $response_hr->{'error_string'} );
    }

    return $response_hr->{'valid'};
}

=head2 host_key_checking()

Return an array of options to be passed to the ssh command to handle host key
checking, depending on tweak settings values.

A caller of this function must be prepared for the case that the remote machine
isn't trusted and prompt the user accordingly to verify that the host key
fingerprint is correct.  Information about the host keys can be queried using
other functions in thie module.

Every option returned by this function will be of the form C<-oOption=value>.

=cut

sub host_key_checking {
    my $value = Cpanel::Config::LoadCpConf::loadcpconf()->{'ssh_host_key_checking'};
    return _host_key_checking( $value || 1 );
}

=head2 host_key_checking_legacy()

Return an array of options to be passed to the ssh command to handle host key
checking, depending on tweak settings values.

This function is for existing uses only and B<must not> be used in new code,
callers, or call sites, since this function may disable host-key checking.

Every option returned by this function will be of the form C<-oOption=value>.

=cut

sub host_key_checking_legacy {

    # DO NOT use this function in new code.
    my $value = Cpanel::Config::LoadCpConf::loadcpconf()->{'ssh_host_key_checking'};
    return _host_key_checking($value);
}

sub _host_key_checking {
    my ($value) = @_;
    if ( !$value ) {
        return ('-oStrictHostKeyChecking=no');
    }
    elsif ( $value eq 'dns' ) {
        return ( '-oStrictHostKeyChecking=yes', '-oVerifyHostKeyDNS=yes' );
    }
    else {
        return ('-oStrictHostKeyChecking=yes');
    }
}

=head2 metadata_from_key($key)

Compute the MD5 and SHA-256 fingerprints for the given public key.

Returns undef on error.

Otherwise, returns a hashref with the following keys:

=over 4

=item algorithm

The key algorithm according to OpenSSH.

=item body

The key body (the Base64-encoded portion).

=item md5

The MD5 key fingerprint in hex.

=item md5-printable

The MD5 key fingerprint in the format typically used by OpenSSH.

=item sha256

The SHA-256 key fingerprint in hex.  This is the format suitable for SSHFP
records.

=item sha256-printable

The SHA-256 key fingerprint in the format typically used by OpenSSH.

=back

=cut

sub metadata_from_key {
    my ($key) = @_;
    my ( $algo, $body64, undef ) = split /\s+/, $key, 3;

    return undef unless defined $body64;
    return undef unless $algo =~ /^(?:ssh-(?:rsa|dss|ed25519)|ecdsa-sha2-nistp(?:256|384|521))$/;

    require MIME::Base64;
    my $body = MIME::Base64::decode_base64($body64);

    require Digest::MD5;
    require Digest::SHA;
    my $md5_hex = lc Digest::MD5::md5_hex($body);
    my $sha256  = Digest::SHA::sha256($body);

    return {
        'algorithm'        => $algo,
        'body'             => $body64,
        'md5'              => $md5_hex,
        'md5-printable'    => 'MD5:' . join( ':', grep { $_ } split /(.{2})/, $md5_hex ),
        'sha256'           => lc unpack( 'H*', $sha256 ),
        'sha256-printable' => 'SHA256:' . MIME::Base64::encode_base64( $sha256, '' ) =~ tr/=//dr,
    };
}

=head2 fetch_host_keys_for_machine($machine, [$port])

Fetch the SSH host keys for the specified machine and port.  If the port is not
specified, default to 22.

The timeout for this operation is 5 seconds.

For security reasons, only RSA, ECDSA, and (on CentOS 7 and newer) Ed25519 keys
are scanned.  DSA keys are ignored because they are limited to 1024 bits and are
therefore insecure.  This behavior is consistent with the defaults for OpenSSH
7.4.

Returns a list of hashrefs representing keys returned from the server.  If the
remote server is not running SSH or otherwise has no host keys, an empty list
will be returned.  An exception will be thrown if the ssh-keyscan binary cannot
be invoked.

Each hashref contains the following

=over 4

=item line

A line suitable for entry into an SSH known_hosts file.

=item host

An SSH-compatible form of the hostname and port.  If using the default port,
this will be equivalent to the hostname.

=item key

The SSH public key.

=back

=cut

sub fetch_host_keys_for_machine {
    my ( $machine, $port ) = @_;
    $port //= 22;

    require Cpanel::OS;
    my @algos = Cpanel::OS::ssh_supported_algorithms()->@*;

    require Cpanel::Binaries;
    my $cmd = Cpanel::SafeRun::Object->new_or_die( program => Cpanel::Binaries::path('ssh-keyscan'), args => [ '-T5', "-p$port", '-t' . join( ',', @algos ), $machine ] );

    my @errors    = grep { !/^(#|$)/ } split /\n/, $cmd->stderr;
    my @host_keys = map {
        my ( $host, $key ) = split /\s+/, $_, 2;
        {
            line => $_,
            host => $host,
            key  => $key,
        }
    } grep { !/^(#|$)/ } split /\n/, $cmd->stdout;

    die Cpanel::Exception::create( 'SystemCall', 'The call to “[_1]” failed because of an error: [_2]', [ 'ssh-keyscan', $errors[0] ] ) if $errors[0] && !scalar @host_keys;

    return @host_keys;
}

1;
