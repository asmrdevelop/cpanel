package Cpanel::Domains;

# cpanel - Cpanel/Domains.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                   ();
use Cpanel::CachedDataStore         ();
use Cpanel::Config::CpUserGuard     ();
use Cpanel::Config::LoadUserDomains ();

our $ENTRY_TTL       = 86400 * 62;                          # Only keep deleted domains for 62 days (Minimum of two longest months 31d*2)
our $VERSION         = '1.2';
our $deleted_db_file = '/var/cpanel/deleteddomains.yaml';

#user, owner, domain, $additional_domains_ar
sub add_deleted_domains {
    return _deleteddomains_op( 'add', @_ );
}

#user, owner, domain, $additional_domains_ar
sub del_deleted_domains {
    return _deleteddomains_op( 'del', @_ );
}

sub load_deleted_db {
    my $write = shift;

    # Usage as safe as we own the dir and file
    my $deleted_db = Cpanel::CachedDataStore::loaddatastore( $deleted_db_file, $write );
    if ( 'HASH' ne ref $deleted_db->{'data'} ) {
        $deleted_db->{'data'} = {};
    }
    return $deleted_db;
}

sub _deleteddomains_op {
    my $op         = shift;
    my $user       = shift;
    my $owner      = shift;
    my $domain     = shift;
    my $domain_ref = shift;

    #
    # Load read only first since we can load from cache
    # if we are not locking
    #
    my $deleted_db_ref = load_deleted_db();
    my @keys_to_delete;
    my %keys_to_add;

    my $now = time();
    my %remove_list;
    foreach my $dname ( $domain, @{$domain_ref} ) {
        next if !$dname;

        if ( $deleted_db_ref->{'data'}{$dname} ) {
            $remove_list{$dname} = $deleted_db_ref->{'data'}{$dname}{'user'};
            push @keys_to_delete, $dname;
        }

        if ( $op eq 'add' ) {
            $keys_to_add{$dname} = {
                'is_main_domain' => ( $dname eq $domain ) ? 1 : 0,
                'user'           => $user,
                'killtime'       => $now,
                'reseller'       => $owner,
            };
            if ( $remove_list{$dname} && $remove_list{$dname} eq $user ) {
                delete $remove_list{$dname};
            }
        }
    }

    my %user_removelist;
    foreach my $dname ( keys %remove_list ) {
        push @{ $user_removelist{ $remove_list{$dname} } }, $dname;
    }

    foreach my $remove_user ( keys %user_removelist ) {
        my $cpuser = Cpanel::Config::CpUserGuard->new($user);
        if ($cpuser) {
            foreach my $remove_dname ( @{ $user_removelist{$remove_user} } ) {
                @{ $cpuser->{'data'}->{'DEADDOMAINS'} } = grep { lc $_ eq lc $remove_dname } @{ $cpuser->{'data'}->{'DEADDOMAINS'} };
            }
            $cpuser->save();
        }
        else {
            Cpanel::Debug::log_warn("Could not update user file for '$user'");
        }
    }

    if ( @keys_to_delete || scalar keys %keys_to_add ) {

        # Delete expired keys as well
        push @keys_to_delete, grep { ( $deleted_db_ref->{'data'}{$_}{'killtime'} || 0 ) + $ENTRY_TTL < $now } keys %{ $deleted_db_ref->{'data'} };
        #
        # Only load read-write if we need to
        $deleted_db_ref = load_deleted_db(1);
        delete @{ $deleted_db_ref->{'data'} }{@keys_to_delete};
        @{ $deleted_db_ref->{'data'} }{ keys %keys_to_add } = values %keys_to_add;
        Cpanel::CachedDataStore::savedatastore( $deleted_db_file, $deleted_db_ref );
    }

    # Usage as safe as we own the dir and file
    chmod 0600, $deleted_db_file;
    return;
}

#  Remove any live domains from a user's dead domains list
sub get_true_user_deaddomains {
    my ($ar_deaddomains) = @_;
    ## from /etc/userdomains
    my $live_domains_hr = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    return grep { !exists $live_domains_hr->{$_} } @$ar_deaddomains;
}

sub change_deleteddomains_reseller {
    my ( $oldreseller, $newreseller ) = @_;

    return _alter_deleted_db_ref_data(
        sub {
            my ($data_ref) = @_;

            my $changed;

            foreach my $entry ( values %$data_ref ) {
                if ( $entry->{'reseller'} eq $oldreseller ) {
                    $entry->{'reseller'} = $newreseller;
                    $changed = 1;
                }
            }

            return $changed;
        }
    );
}

sub change_deleteddomains_user {
    my ( $olduser, $newuser ) = @_;

    my $changed = 0;
    _alter_deleted_db_ref_data(
        sub {
            my ($data_ref) = @_;

            foreach my $entry ( values %$data_ref ) {
                if ( $entry->{'user'} eq $olduser ) {
                    $entry->{'user'} = $newuser;
                    $changed++;
                }
            }

            return $changed;
        }
    );

    return $changed;
}

sub remove_deleteddomains_by_user {
    my ($user) = @_;

    my $removed = 0;

    _alter_deleted_db_ref_data(
        sub {
            my ($data_ref) = @_;
            my @to_delete = grep { $data_ref->{$_}{user} eq $user } keys %$data_ref;
            delete @{$data_ref}{@to_delete} if @to_delete;
            $removed = scalar @to_delete;
            return $removed;
        }
    );

    return $removed;
}

#returns whether was changed or not
sub _alter_deleted_db_ref_data {
    my ($todo_cr) = @_;

    my $deleted_db_ref = load_deleted_db(1);

    my $changed = $todo_cr->( $deleted_db_ref->{'data'} );

    if ($changed) {
        Cpanel::CachedDataStore::savedatastore( $deleted_db_file, $deleted_db_ref );
    }
    else {
        Cpanel::CachedDataStore::unlockdatastore($deleted_db_ref);
    }

    # Usage as safe as we own the dir and file
    chmod 0600, $deleted_db_file;

    return;
}

1;
