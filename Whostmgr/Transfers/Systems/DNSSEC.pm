package Whostmgr::Transfers::Systems::DNSSEC;

# cpanel - Whostmgr/Transfers/Systems/DNSSEC.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::LoadFile ();
use parent 'Whostmgr::Transfers::Systems';

=head1 NAME

Whostmgr::Transfers::Systems::DNSSEC - A Transfer Systems module to restore a user's DNSSEC keys

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::DNSSEC;

    my $transfer = Whostmgr::Transfers::Systems::DNSSEC->new(
         utils => $whostmgr_transfers_utils_obj,
         archive_manager => $whostmgr_transfers_archivemanager_obj,
    );
    $transfer->unrestricted_restore();

=head1 DESCRIPTION

This module implements a C<Whostmgr::Transfers::Systems> module. It is responsible for restoring the
DNSSEC keys for a given user.

=head1 METHODS

=cut

=head2 get_phase()

Override the default phase for a C<Whostmgr::Transfers::Systems> module.

=cut

sub get_phase { return 75; }    # after ZoneFile but before Post

=head2 get_prereq()

Override the default prereq for a C<Whostmgr::Transfers::Systems> module.

=cut

sub get_prereq {
    return ['ZoneFile'];
}

=head2 get_summary()

Provide a summary of what this module is supposed to do.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module restores the DNSSEC keys for an account.') ];
}

=head2 get_restricted_available()

Mark this module as available for retricted restores.

=cut

sub get_restricted_available {
    return 1;
}

=head2 unrestricted_restore()

The function that actually does the work of restoring the DNSSEC keys for a user.

This method is also aliased to C<restricted_restore>.

B<Returns>: C<1>

=cut

sub unrestricted_restore {
    my ($self) = @_;

    require Cpanel::NameServer::Conf;

    my $dns_obj = Cpanel::NameServer::Conf->new();
    return 1 if $dns_obj->type() ne 'powerdns';

    my @domains    = $self->{'_utils'}->domains();
    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();
    my $dnssec_dir = "$extractdir/dnssec_keys";

    foreach my $domain (@domains) {
        my $domain_dnssec_dir = "$dnssec_dir/$domain";
        next if !-d $domain_dnssec_dir;

        if ( opendir my $dh, $domain_dnssec_dir ) {
            $self->start_action("Restoring DNSSEC Keys for $domain");
            while ( my $filename = readdir $dh ) {
                if ( $filename =~ m/^[0-9]+_([KCZ]SK)\.key$/ ) {
                    my $key_type = lc($1);

                    # 'CSK' isn't a valid key type on import.
                    # CSKs are basically KSKs that are used as a ZSK if a ZSK isn't present.
                    $key_type = 'ksk'
                      if $key_type eq 'csk';

                    my $key_content = Cpanel::LoadFile::load_if_exists("$domain_dnssec_dir/$filename");
                    next if !$key_content;

                    my $import = $dns_obj->import_zone_key( $domain, $key_content, $key_type );
                    if ( $import->{'success'} ) {
                        $self->out( $self->_locale()->maketext( "Restored [_1] for [_2].", uc($key_type), $domain ) );
                    }
                    elsif ( $import->{'error'} ) {
                        $self->warn( $self->_locale()->maketext( "Failed to restore [_1] for [_2]: [_3]", uc($key_type), $domain, $import->{'error'} ) );
                    }
                }
            }
        }
    }

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 30, "restartsrv pdns" );

    return 1;
}

*restricted_restore = *unrestricted_restore;

1;
