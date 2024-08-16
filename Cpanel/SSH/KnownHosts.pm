package Cpanel::SSH::KnownHosts;

# cpanel - Cpanel/SSH/KnownHosts.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf ();
use Cpanel::Exception          ();
use Cpanel::Locale             ();
use Cpanel::PwCache            ();
use Cpanel::SafeRun::Object    ();
use Cpanel::SSH::Key           ();

=head1 NAME

Cpanel::SSH::KnownHosts

=head1 DESCRIPTION

Provides a set of functions to work with ~/.ssh/known_hosts file.

=head1 FUNCTIONS

=cut

=head2 fetch_host_keys($host, [$port])

Fetch the SSH host keys for the specified host and port.  If the port is not
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

=item meta

Meta data associated with the key, such as algorithms and fingerprints.

=back

=cut

sub fetch_host_keys {
    my ( $host, $port ) = @_;

    my (@host_keys) = Cpanel::SSH::Key::fetch_host_keys_for_machine( $host, $port );

    foreach my $key (@host_keys) {
        $key->{'meta'} = Cpanel::SSH::Key::metadata_from_key( $key->{'key'} );
    }

    return \@host_keys;
}

=head2 get_known_host_keys($host, [$port])

Retrieve SSH keys for the specified host stored in the known_hosts file.

Returns a list of hashrefs representing keys.  If the host does not exist in
known_hosts, an empty list will be returned.  An exception will be thrown if
the ssh-keygen binary cannot be invoked.

Each hashref contains the following

=over 4

=item line

A line suitable for entry into an SSH known_hosts file.

=item host

An SSH-compatible form of the hostname and port.  If using the default port,
this will be equivalent to the hostname.

=item key

The SSH public key.

=item meta

Meta data associated with the key, such as algorithms and fingerprints.

=back

=cut

sub get_known_host_keys {
    my ( $host, $port ) = @_;

    if ( defined $port ) {
        $host = "[$host]:$port";
    }

    require Cpanel::Binaries;
    my $cmd = Cpanel::SafeRun::Object->new( program => Cpanel::Binaries::path('ssh-keygen'), args => [ '-F', $host ] );

    my @host_keys = map {
        my ( $host, $key ) = split /\s+/, $_, 2;
        {
            line => $_,
            host => $host,
            key  => $key,
        }
    } grep { !/^(#|$)/ } split /\n/, $cmd->stdout;

    foreach my $key (@host_keys) {
        $key->{'meta'} = Cpanel::SSH::Key::metadata_from_key( $key->{'key'} );
    }

    return \@host_keys;
}

=head2 remove_known_host($host, [$port])

Delete all SSH keys for the specified host from the known_hosts file. An exception
will be thrown if the ssh-keygen binary cannot be invoked.

=cut

sub remove_known_host {
    my ( $host, $port ) = @_;

    my $host_keys_file = _known_hosts_file();
    return unless -e $host_keys_file;

    if ( defined $port ) {
        $host = "[$host]:$port";
    }

    require Cpanel::Binaries;
    my $cmd = Cpanel::SafeRun::Object->new_or_die( program => Cpanel::Binaries::path('ssh-keygen'), args => [ '-R', $host ] );

    return;
}

=head2 add_to_known_hosts($host, [$port])

Fetch the SSH host keys for the specified host and port, and add them to the
known_hosts file. Any previously existing entries for the specified host and
port will be removed. If the port is not specified, default to 22.

The timeout for this operation is 5 seconds.

For security reasons, only RSA, ECDSA, and (on CentOS 7 and newer) Ed25519 keys
are scanned.  DSA keys are ignored because they are limited to 1024 bits and are
therefore insecure.  This behavior is consistent with the defaults for OpenSSH
7.4.

Returns a list of hashrefs representing keys returned from the server.  If the
remote server is not running SSH or otherwise has no host keys, an empty list
will be returned.  An exception will be thrown if the ssh-keyscan binary cannot
be invoked or known_hosts file can not be written into.

Each hashref contains the following

=over 4

=item line

A line suitable for entry into an SSH known_hosts file.

=item host

An SSH-compatible form of the hostname and port.  If using the default port,
this will be equivalent to the hostname.

=item key

The SSH public key.

=item meta

Meta data associated with the key, such as algorithms and fingerprints.

=back

=cut

sub add_to_known_hosts {
    my ( $host, $port ) = @_;

    my $host_keys = fetch_host_keys( $host, $port );
    remove_known_host( $host, $port );

    my $host_keys_file = _known_hosts_file();

    open my $fh, '>>', $host_keys_file
      or die Cpanel::Exception::create( 'IO::FileOpenError', [ 'path' => $host_keys_file, 'mode' => '>>', 'error' => $! ] );

    foreach my $key (@$host_keys) {
        print $fh $key->{'line'}, "\n";
    }

    close $fh;
    return $host_keys;
}

=head2 check_known_hosts($host, [$port])

Check if a host exists in known_hosts and if the key signatures are the same
as the remote host. An exception will be thrown if host keys can not be
retrieved from remote host or known_hosts file.

Returns a status code, and in the case of failure, a hashref that contains the
following:

=over 4

=item type

The failure type, whether the keys are new or out of date.

=item error

An error message that describes the failure.

=item host_keys

A hashref that contains host key information returned from fetch_host_keys.

=back

=cut

sub check_known_hosts {
    my ( $host, $port ) = @_;

    my $value = Cpanel::Config::LoadCpConf::loadcpconf()->{'ssh_host_key_checking'};
    return 1 if !$value;

    my $known_host_keys = get_known_host_keys( $host, $port );
    my $host_keys       = fetch_host_keys( $host, $port );
    my $locale          = _locale();
    return 0,
      {
        'type'      => 'new',
        'error'     => $locale->maketext( "The host “[_1]” does not exist in the [asis,known_hosts] file.", $host ),
        'host_keys' => $host_keys
      }
      unless scalar @$known_host_keys;

    my %known_host_keys_hash = map { $_->{'meta'}{'algorithm'} => $_->{'meta'}{'sha256'} } @$known_host_keys;
    foreach my $key (@$host_keys) {
        my $algo = $key->{'meta'}{'algorithm'};
        unless ( $known_host_keys_hash{$algo} && $known_host_keys_hash{$algo} eq $key->{'meta'}{'sha256'} ) {
            return 0,
              {
                'type'      => 'changed',
                'error'     => $locale->maketext( "The keys for the “[_1]” host in the [asis,known_hosts] file are out of date.", $host ),
                'host_keys' => $host_keys
              };
        }
    }

    return 1;
}

my $_locale;
my $known_hosts_file;

sub _locale {
    return $_locale ||= Cpanel::Locale->get_handle();
}

sub _known_hosts_file {
    return $known_hosts_file if $known_hosts_file;

    my $homedir = Cpanel::PwCache::gethomedir();
    mkdir "$homedir/.ssh", 0700 unless -e "$homedir/.ssh";

    return "$homedir/.ssh/known_hosts";
}

1;
