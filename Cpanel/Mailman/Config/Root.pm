package Cpanel::Mailman::Config::Root;

# cpanel - Cpanel/Mailman/Config/Root.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::PwCache                      ();
use Cpanel::FileUtils::Write             ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Mailman::Filesys             ();
use Cpanel::Mailman::NameUtils           ();
use Cpanel::Mailman::Utils               ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::SafeDir::MK                  ();

#Constant
my $CREATE_IF_NEEDED = 1;

#Named parameters:
#   - user - The cpanel user who owns the lists.
#
sub new {
    my ( $class, %opts ) = @_;

    if ( $> != 0 ) {
        die "This package: " . __PACKAGE__ . " must run as root.";
    }

    my @user_pwnam = Cpanel::PwCache::getpwnam( $opts{'user'} );

    if ( !$user_pwnam[2] ) {
        die "“$opts{'user'}” appears not to be a user on this system.";
    }

    my $self = {
        'user'    => $user_pwnam[0],
        'uid'     => $user_pwnam[2],
        'gid'     => $user_pwnam[3],
        'homedir' => $user_pwnam[7],
    };

    bless $self, $class;

    return $self;
}

sub recache_users_mailmanconfig {
    my ( $self, $listids_ref ) = @_;

    my $MAILING_LISTS_DIR = Cpanel::Mailman::Filesys::MAILING_LISTS_DIR();
    my $configcache_dir   = $self->_configcache_dir($CREATE_IF_NEEDED);

    my %results;
    my @lists_to_dump;
    foreach my $list ( @{$listids_ref} ) {
        my $normalized_list = Cpanel::Mailman::NameUtils::normalize_name($list);
        my @list_parts      = eval { Cpanel::Mailman::NameUtils::parse_name($normalized_list) };

        if ( !@list_parts ) {
            $results{$list} = [ 0, "$list is not a valid list name" ];
            next;
        }

        my $list_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $list_parts[-1] );

        if ( $list_owner ne $self->{'user'} ) {
            $results{$list} = [ 0, "$list is not owned by user" ];
            next;
        }

        my $cache_mtime = ( stat("$configcache_dir/$list") )[9];
        my $config_pck  = Cpanel::Mailman::Filesys::get_list_dir($list) . '/config.pck';

        # If config pickle is missing, attempt to restore it.
        if ( !-e $config_pck ) {
            Cpanel::SafeRun::Simple::saferun( Cpanel::Mailman::Filesys::MAILMAN_DIR() . '/bin/check_db', $list );
            if ( !-e $config_pck ) {
                $results{$list} = [ 0, "Config file for $list is missing" ];
                next;
            }
        }

        my $config_mtime = ( stat($config_pck) )[9];
        if ( $config_mtime && $cache_mtime && $cache_mtime > $config_mtime ) {
            $results{$list} = [ 1, "Cache file for $list is up to date" ];
            next;
        }

        push @lists_to_dump, $list;
    }

    my %exec;

    if (@lists_to_dump) {
        my $pickle_files = join( ',', map { Cpanel::Mailman::Filesys::get_list_dir($_) . '/config.pck' } @lists_to_dump );

        my ( @all_json, $err );
        try {
            @all_json = Cpanel::Mailman::Utils::get_cpanel_mailmancfg_json(@lists_to_dump);
        }
        catch {
            $err = $_;
        };

        return ( 0, $err ) if $err;

        for ( 0 .. $#lists_to_dump ) {
            my $dump_list = $lists_to_dump[$_];
            my $json      = $all_json[$_];
            if ($json) {
                $exec{$dump_list} = sub {
                    $self->_write_list_cache( $dump_list, \$json );
                }
            }
            else {
                $results{$dump_list} = [ 0, "Failed to dump config for $dump_list" ];
            }
        }
    }

    if ( scalar keys %exec ) {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                foreach my $task ( sort keys %exec ) {
                    $results{$task} = [ $exec{$task}->() ];
                }
            },
            $self->{'uid'},
            $self->{'gid'}
        );
    }

    return ( 1, "Built cache", \%results );
}

sub _configcache_dir {
    my ( $self, $should_create ) = @_;

    my $configcache_dir = $self->{'homedir'} . Cpanel::Mailman::Filesys::CONFIGCACHE_DIR_REL_HOMEDIR();

    if ( $should_create && $should_create == $CREATE_IF_NEEDED && !-e $configcache_dir ) {
        if ( !Cpanel::AccessIds::ReducedPrivileges::call_as_user( sub { Cpanel::SafeDir::MK::safemkdir( $configcache_dir, 0700 ); }, $self->{'uid'}, $self->{'gid'} ) ) {
            die "Failed to make directory: $configcache_dir: $!";
        }
    }

    return $configcache_dir;

}

sub _write_list_cache {
    my ( $self, $dump_list, $json_ref ) = @_;

    my $configcache_dir = $self->_configcache_dir();

    if ( Cpanel::FileUtils::Write::overwrite_no_exceptions( "$configcache_dir/$dump_list", $$json_ref, 0600 ) ) {
        return ( 1, "Updated cache for $dump_list" );
    }
    return ( 0, "Failed to write JSON cache for list $dump_list: $!" );

}

1;
