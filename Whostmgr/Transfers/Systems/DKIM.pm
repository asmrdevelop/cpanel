package Whostmgr::Transfers::Systems::DKIM;

# cpanel - Whostmgr/Transfers/Systems/DKIM.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK

# This module doesn’t need to be worker-aware because the controller is
# authoritative for the domain keys anyway.
use base qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::OrDie      ();
use Cpanel::DKIM       ();
use Cpanel::DKIM::Save ();
use Cpanel::LoadFile   ();

my $MAX_KEY_FILE_BYTES = 1024 * 1024;    #1 MiB

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [output,acronym,DKIM,DomainKeys Identified Mail] keys and updates records for the current server.') ];
}

sub get_restricted_available {
    return 1;
}

#We only care about the *private* key file because
#we regenerate the public key from the private. This reduces the chance of
#error and also doubles as validation of the private key file.
sub restricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    # create missing directories if needed
    Cpanel::DKIM::setup_file_stores();    # audited -- safe, does not accept user input

    my $newuser = $self->{'_utils'}->local_username();

    my @all_domains    = $self->{'_utils'}->domains();
    my %domains_lookup = map { $_ => undef } @all_domains;

    my $private_dir = "$extractdir/domainkeys/private";

    if ( !-e "$extractdir/domainkeys" ) {
        return ( 1, $self->_locale()->maketext("The account does not have any [output,asis,DKIM] keys to restore.") );
    }

    opendir my $dh, $private_dir or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to open the directory “[_1]” because of an error: [_2]', $private_dir, $! ) );
    };

    my @domains = grep { exists $domains_lookup{$_} } readdir $dh;

    closedir $dh or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to close the directory “[_1]” because of an error: [_2]', $private_dir, $! ) );
    };

  DOMAIN:
    for my $domain (@domains) {
        my ( $ok, $err ) = $self->_do_domain_restore($domain);

        if ( !$ok ) {
            $err .= q{ } . $self->_locale()->maketext( 'The system will not restore “[_1]”’s archived DKIM keys.', $domain );

            $self->warn($err);

            next DOMAIN;
        }
    }

    return ( 1, 'DKIM restored' );    #TODO check for failure
}

*unrestricted_restore = \&restricted_restore;

#In addition to the normal I/O checks, this checks that:
#   - The private key file is not overly large.
#   - The private key file is valid.
sub _do_domain_restore {
    my ( $self, $domain ) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $archive_key_path = "$extractdir/domainkeys/private/$domain";

    my $keyfile_size = ( lstat $archive_key_path )[7];
    if ( $keyfile_size > $MAX_KEY_FILE_BYTES ) {
        return ( 0, $self->_locale()->maketext( 'The key file “[_1]” is too large ([format_bytes,_2]).', $archive_key_path, $keyfile_size ) );
    }

    my $private_key = Cpanel::LoadFile::loadfile($archive_key_path) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to load the file “[_1]” because of an error: [_2]', $archive_key_path, $_ ) );
    };

    my ( $ok, $err ) = Cpanel::OrDie::convert_die_to_multi_return( sub { Cpanel::DKIM::Save::save( $domain, $private_key ) } );

    if ( !$ok ) {
        my $newuser = $self->{'_utils'}->local_username();
        Cpanel::DKIM::Save::delete( $domain, $newuser );
    }

    return ( $ok, $err );
}

1;
