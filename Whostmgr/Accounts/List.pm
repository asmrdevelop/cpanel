package Whostmgr::Accounts::List;

# cpanel - Whostmgr/Accounts/List.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf         ();
use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::Config::LoadUserDomains    ();
use Cpanel::Config::LoadUserOwners     ();
use Cpanel::Config::userdata::Cache    ();
use Cpanel::Config::userdata::Load     ();
use Cpanel::Email::DeferThreshold      ();
use Cpanel::Email::Mailbox::Format     ();
use Cpanel::LinkedNode::Worker::GetAll ();
use Cpanel::PwCache                    ();
use Cpanel::PwCache::Build             ();
use Cpanel::PwCache::Helpers           ();
use Cpanel::StringFunc::Case           ();
use Cpanel::Sys::Hostname              ();
use Cpanel::SysQuota                   ();
use Cpanel::Timezones                  ();
use Whostmgr::ACLS                     ();
use Whostmgr::Accounts::Suspended      ();
use Whostmgr::AcctInfo::Plans          ();
use Whostmgr::DateTime                 ();
use Whostmgr::Quota::User              ();

sub listaccts {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    my $search_regex;
    if ( defined $OPTS{'search'} && $OPTS{'search'} ne '' ) {
        $OPTS{'search'} =~ s/\n//g;    # Remove newlines JIC
        eval {
            local $SIG{'__DIE__'} = sub { return };
            $search_regex = qr/$OPTS{'search'}/i;
        };
    }

    # Set search regex to a "match all"
    if ( !$search_regex ) {
        $search_regex = qr/./;
    }

    my $is_one_user = ( ( $OPTS{'searchmethod'} || '' ) eq 'exact' && ( $OPTS{'searchtype'} || '' ) eq 'user' );
    my ( %HOMES, %IPS, %SHELLS, %UIDS, %ALLCPD );
    my $truedomains;
    my $user_owner_hr;

    if ($is_one_user) {
        my @pw = Cpanel::PwCache::getpwnam_noshadow( $OPTS{'search'} );
        if ( !$pw[0] ) {
            return;
        }
        $HOMES{ $pw[0] } = $pw[7];
    }
    else {
        Cpanel::PwCache::Helpers::no_uid_cache();                                                               #uid cache only needed if we are going to make lots of getpwuid calls
        if ( Cpanel::PwCache::Build::pwcache_is_initted() != 2 ) { Cpanel::PwCache::Build::init_pwcache(); }    # we need to look at the password hashes
    }
    my $server = Cpanel::Sys::Hostname::gethostname();
    my $pwcache_ref;

    if ( !$is_one_user ) {
        $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();
        %HOMES       = map { $_->[0] => $_->[7] } @$pwcache_ref;
    }

    my $can_see_all_accts = Whostmgr::ACLS::hasroot() || ( $ENV{'REMOTE_USER'} eq 'root' && Whostmgr::ACLS::checkacl('list-accts') );
    my $built_ips         = 0;
    my ( $quota_used_map, $quota_limit_map, $quota_version, $inodes_used_map, $inodes_limit_map, $userdata );
    if ($is_one_user) {
        my $cpuserfile_name = $OPTS{'search'} eq 'root' ? 'system' : $OPTS{'search'};
        my $cpuser_ref      = Cpanel::Config::LoadCpUserFile::load($cpuserfile_name);
        if ( scalar keys %{$cpuser_ref} ) {
            $ALLCPD{ $OPTS{'search'} }                = $cpuser_ref;
            $truedomains->{ $cpuser_ref->{'DOMAIN'} } = $OPTS{'search'};
            $user_owner_hr->{ $OPTS{'search'} }       = $cpuser_ref->{'OWNER'} || 'root';
            my $user_data = Cpanel::Config::userdata::Load::load_userdata_domain( $OPTS{'search'}, $cpuser_ref->{'DOMAIN'}, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
            $IPS{ $cpuser_ref->{'DOMAIN'} } = $user_data->{'ip'};
            $built_ips = 1;
        }
        $userdata = Cpanel::Config::userdata::Cache::load_cache($cpuserfile_name);
        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

        my $quota_data = Whostmgr::Quota::User::get_users_quota_data( $cpuserfile_name, { include_mailman => $cpconf->{'disk_usage_include_mailman'}, include_sqldbs => $cpconf->{'disk_usage_include_sqldbs'} } );
        my ( $used, $limit, $remain, $inodes_used, $inodes_limit, $inodes_remain ) =
          @{$quota_data}{qw(bytes_used bytes_limit bytes_remain inodes_used inodes_limit inodes_remain)};
        $quota_used_map->{$cpuserfile_name}   = $used  ? ( $used / 1024 )  : undef;
        $quota_limit_map->{$cpuserfile_name}  = $limit ? ( $limit / 1024 ) : undef;
        $inodes_used_map->{$cpuserfile_name}  = $inodes_used;
        $inodes_limit_map->{$cpuserfile_name} = $inodes_limit;
        ( $UIDS{$cpuserfile_name}, $SHELLS{$cpuserfile_name} ) = ( Cpanel::PwCache::getpwnam($cpuserfile_name) )[ 2, 8 ];
        return if ( !$can_see_all_accts && $user_owner_hr->{ $OPTS{'search'} } ne $ENV{'REMOTE_USER'} );
    }
    else {
        $userdata = Cpanel::Config::userdata::Cache::load_cache();
        %SHELLS   = map { $_->[0] => $_->[8] } @$pwcache_ref;
        %UIDS     = map { $_->[0] => $_->[2] } @$pwcache_ref;

        ( $quota_used_map, $quota_limit_map, $quota_version, $inodes_used_map, $inodes_limit_map ) = Cpanel::SysQuota::analyzerepquotadata();

        # 1 as third argument ignores the license’s user limit,
        # so we display all accounts.
        $truedomains = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( -1, undef, 1 );

        if ( !$can_see_all_accts || ( length $OPTS{'search'} && $OPTS{'searchtype'} eq 'owner' ) ) {
            $user_owner_hr ||= Cpanel::Config::LoadUserOwners::loadtrueuserowners( -1, 1, 1 );
        }
        delete @{$truedomains}{ grep { $user_owner_hr->{ $truedomains->{$_} } ne $ENV{'REMOTE_USER'} } keys %{$truedomains} } if !$can_see_all_accts;
        if ( length $OPTS{'search'} ) {

            # Only used when searchtype eq 'package'
            my $userplan_ref;

            my $lowercase_search = Cpanel::StringFunc::Case::ToLower( $OPTS{'search'} );
            if ( $OPTS{'searchtype'} eq 'ip' ) {
                %IPS       = map { $_ => ( ( split( /:/, $userdata->{$_}->[5] ) )[0] || '*unknown*' ) } keys %{$truedomains} if !$built_ips;
                $built_ips = 1;
            }
            elsif ( $OPTS{'searchtype'} eq 'package' ) {
                $userplan_ref = Whostmgr::AcctInfo::Plans::loaduserplans();
            }

            if ( $OPTS{'searchmethod'} && $OPTS{'searchmethod'} eq 'exact' ) {
                if ( $OPTS{'searchtype'} eq 'domain' ) {
                    delete @{$truedomains}{ grep { Cpanel::StringFunc::Case::ToLower($_) ne $lowercase_search } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'ip' ) {
                    delete @{$truedomains}{ grep { $IPS{$_} ne $OPTS{'search'} } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'user' ) {
                    delete @{$truedomains}{ grep { $truedomains->{$_} ne $lowercase_search } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'package' ) {
                    delete @{$truedomains}{ grep { $userplan_ref->{ $truedomains->{$_} } ne $OPTS{'search'} } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'owner' ) {
                    delete @{$truedomains}{ grep { $user_owner_hr->{ $truedomains->{$_} } ne $lowercase_search } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'domain_and_user' ) {
                    delete @{$truedomains}{ grep { $truedomains->{$_} ne $search_regex && $_ ne $search_regex } keys %{$truedomains} };
                }
            }
            else {
                if ( $OPTS{'searchtype'} eq 'domain' ) {
                    delete @{$truedomains}{ grep { $_ !~ $search_regex } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'ip' ) {
                    delete @{$truedomains}{ grep { $IPS{$_} !~ $search_regex } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'user' ) {
                    delete @{$truedomains}{ grep { $truedomains->{$_} !~ $search_regex } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'package' ) {
                    delete @{$truedomains}{ grep { ( $userplan_ref->{ $truedomains->{$_} } // '' ) !~ $search_regex } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'owner' ) {
                    delete @{$truedomains}{ grep { $user_owner_hr->{ $truedomains->{$_} } !~ $search_regex } keys %{$truedomains} };
                }
                elsif ( $OPTS{'searchtype'} eq 'domain_and_user' ) {
                    delete @{$truedomains}{ grep { $truedomains->{$_} !~ $search_regex && $_ !~ $search_regex } keys %{$truedomains} };
                }
            }
        }
        else {
            %IPS = map { $_ => ( ( split( /:/, $userdata->{$_}->[5] || '' ) )[0] || '*unknown*' ) } grep $_, keys %{$truedomains} if !$built_ips;
            $built_ips = 1;
        }
    }
    my ( $user, $domain );
    delete @{$truedomains}{ grep { !exists $HOMES{ $truedomains->{$_} } } keys %{$truedomains} };

    my $susp_search;
    if ($is_one_user) {
        $susp_search = $OPTS{'search'};
    }
    else {

        #auto-vivify
        @{$susp_search}{ values %$truedomains } = ();
    }

    my ( $rSUSPEND, $rSUSREASON, $rSUSTIME, $rSUSLOCKED ) = Whostmgr::Accounts::Suspended::getsuspendedlist(
        1,    #fetchtime … ??
        $susp_search,
        \%ALLCPD,
    );

    local $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env() if !$ENV{'TZ'};
    my $defer_threshold = ( Cpanel::Email::DeferThreshold::defer_threshold() || 0 );
    my $mailbox_format_for_new_accounts;
    return (
        scalar keys %{$truedomains},
        [
            map {
                ( $user, $domain ) = ( $truedomains->{$_}, $_ );

                $ALLCPD{$user} ||= Cpanel::Config::LoadCpUserFile::load($user);

                if ( defined( $ALLCPD{$user}->{'BACKUP'} ) ) {
                    if   ( $ALLCPD{$user}->{'BACKUP'} == 1 ) { $ALLCPD{$user}->{'BACKUP'} = 1; }
                    else                                     { $ALLCPD{$user}->{'BACKUP'} = 0; }
                }
                else { $ALLCPD{$user}->{'BACKUP'} = 0; }
                if ( defined( $ALLCPD{$user}->{'LEGACY_BACKUP'} ) ) {
                    if   ( $ALLCPD{$user}->{'LEGACY_BACKUP'} == 1 ) { $ALLCPD{$user}->{'LEGACY_BACKUP'} = 1; }
                    else                                            { $ALLCPD{$user}->{'LEGACY_BACKUP'} = 0; }
                }
                else { $ALLCPD{$user}->{'LEGACY_BACKUP'} = 0; }

                my $child_nodes_hr = Cpanel::LinkedNode::Worker::GetAll::get_lookup_from_cpuser( $ALLCPD{$user} );

                my $child_nodes_ar = [];
                for my $node_type ( keys %$child_nodes_hr ) {
                    push @$child_nodes_ar, { workload => $node_type, alias => $child_nodes_hr->{$node_type}{alias} } if $child_nodes_hr->{$node_type};
                }

                # NOTE: When adding new fields to this output keep in mind that this code is used by both the
                # listaccts and the accountsummary APIs and that documentation will need to be updated in both.
                {
                    'suspended'               => ( $rSUSPEND->{$user} ? 1                                       : 0 ),
                    'suspendreason'           => ( $rSUSPEND->{$user} ? ( $rSUSREASON->{$user} || '*unknown*' ) : 'not suspended' ),
                    'suspendtime'             => ( $rSUSTIME->{$user} || 0 ),
                    'is_locked'               => ( $rSUSLOCKED->{$user} ? 1 : 0 ),
                    'domain'                  => ( $domain                                                                                                         || '*unknown*' ),
                    'ip'                      => ( ( $built_ips ? $IPS{$domain} : ( defined $userdata->{$domain} && split( /:/, $userdata->{$domain}->[5] ) )[0] ) || '*unknown*' ),
                    'ipv6'                    => [ map { my @parts = split(','); $parts[0] } split( /\s/, $userdata->{$domain}->[7] || '' ) ],
                    'user'                    => ( $user || '*unknown*' ),
                    'outgoing_mail_suspended' => $ALLCPD{$user}->{'OUTGOING_MAIL_SUSPENDED'} ? 1 : 0,
                    'outgoing_mail_hold'      => $ALLCPD{$user}->{'OUTGOING_MAIL_HOLD'}      ? 1 : 0,
                    'email'                   => (
                        length $ALLCPD{$user}->{'CONTACTEMAIL'}
                        ? ( $ALLCPD{$user}->{'CONTACTEMAIL'} . ( $ALLCPD{$user}->{'CONTACTEMAIL2'} ? ', ' . $ALLCPD{$user}->{'CONTACTEMAIL2'} : '' ) )

                          # No need to look this up as it will always be in the cpanel users file if it
                          # is set as of v60 (since sync_contact_emails_to_cpanel_users_files was run and we always updated it now)
                        : '*unknown*'
                    ),
                    'shell'          => $SHELLS{$user} || '*unknown*',
                    'uid'            => $UIDS{$user},
                    'mailbox_format' => ( $ALLCPD{$user}->{'MAILBOX_FORMAT'} || ( $mailbox_format_for_new_accounts ||= Cpanel::Email::Mailbox::Format::get_mailbox_format_for_new_accounts() ) ),
                    'startdate'      => scalar(
                        $ALLCPD{$user}->{'STARTDATE'}
                        ? Whostmgr::DateTime::format_date( $ALLCPD{$user}->{'STARTDATE'} )
                        : '*unknown*'
                    ),
                    'unix_startdate' => ( int( $ALLCPD{$user}->{'STARTDATE'} || 0 ) || '*unknown*' ),
                    'partition'      => ( ( split( /\//, $HOMES{$user}, 3 ) )[1]    || '*unknown*' ),

                    'disklimit' => ( $quota_limit_map->{$user} ? int( ( $quota_limit_map->{$user} / 1024 ) ) . 'M' : 'unlimited' ),
                    'diskused'  => ( $quota_used_map->{$user}  ? int( ( $quota_used_map->{$user} / 1024 ) ) . 'M'  : 'none' ),

                    'inodeslimit' => ( $inodes_limit_map->{$user} || 'unlimited' ),
                    'inodesused'  => ( $inodes_used_map->{$user}  || 'none' ),

                    'backup'        => ( defined $ALLCPD{$user}->{'BACKUP'}        ? $ALLCPD{$user}->{'BACKUP'}        : 1 ),
                    'legacy_backup' => ( defined $ALLCPD{$user}->{'LEGACY_BACKUP'} ? $ALLCPD{$user}->{'LEGACY_BACKUP'} : 1 ),

                    'plan'                                 => ( $ALLCPD{$user}->{'PLAN'}  || 'undefined' ),
                    'theme'                                => ( $ALLCPD{$user}->{'RS'}    || '*unknown*' ),
                    'owner'                                => ( $ALLCPD{$user}->{'OWNER'} || 'root' ),
                    'maxaddons'                            => ( $ALLCPD{$user}->{'MAXADDON'}                  // '*unknown*' ),
                    'maxftp'                               => ( $ALLCPD{$user}->{'MAXFTP'}                    // '*unknown*' ),
                    'maxlst'                               => ( $ALLCPD{$user}->{'MAXLST'}                    // '*unknown*' ),
                    'maxparked'                            => ( $ALLCPD{$user}->{'MAXPARK'}                   // '*unknown*' ),
                    'maxpop'                               => ( $ALLCPD{$user}->{'MAXPOP'}                    // '*unknown*' ),
                    'maxsql'                               => ( $ALLCPD{$user}->{'MAXSQL'}                    // '*unknown*' ),
                    'maxsub'                               => ( $ALLCPD{$user}->{'MAXSUB'}                    // '*unknown*' ),
                    'max_emailacct_quota'                  => ( $ALLCPD{$user}->{'MAX_EMAILACCT_QUOTA'}       // '*unknown*' ),
                    'max_email_per_hour'                   => ( $ALLCPD{$user}->{'MAX_EMAIL_PER_HOUR'}        // '*unknown*' ),
                    'max_defer_fail_percentage'            => ( $ALLCPD{$user}->{'MAX_DEFER_FAIL_PERCENTAGE'} // '*unknown*' ),
                    'min_defer_fail_to_trigger_protection' => ($defer_threshold),
                    'temporary'                            => ( ( $ALLCPD{$user}->{'PLAN'} && $ALLCPD{$user}->{'PLAN'} =~ /cPanel\s+Ticket\s+System/i ) ? 1 : 0 ),    # Set by autofixer2 create_temp_reseller_for_ticket_access when customer support logs into a system
                    'child_nodes'                          => $child_nodes_ar,
                }
              }
              keys %{$truedomains}
        ]
    );
}

sub listsuspended {
    my ( $rSUSPEND, $rSUSREASON, $rSUSTIME, $rSUSLOCKED ) = Whostmgr::Accounts::Suspended::getsuspendedlist(1);

    my @RSD;
    my $owner_ref         = Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );
    my $can_see_all_accts = Whostmgr::ACLS::hasroot() || ( $ENV{'REMOTE_USER'} eq 'root' && Whostmgr::ACLS::checkacl('list-accts') );
    foreach my $user ( keys %{$rSUSPEND} ) {
        if ( $can_see_all_accts || $owner_ref->{$user} eq $ENV{'REMOTE_USER'} ) {
            push @RSD, { 'user' => $user, 'time' => scalar localtime( $rSUSTIME->{$user} || 0 ), 'unixtime' => $rSUSTIME->{$user}, 'owner' => $owner_ref->{$user}, 'reason' => $rSUSREASON->{$user}, 'is_locked' => $rSUSLOCKED->{$user} };
        }
    }
    return \@RSD;
}

sub getlockedlist {
    my @lockedlist;

    if ( opendir my $fh, '/var/cpanel/suspended' ) {
        while ( my $filename = readdir $fh ) {
            if ( $filename =~ m{\A(.*)\.lock\z} ) {
                push @lockedlist, $1;
            }
        }
    }

    return wantarray ? @lockedlist : \@lockedlist;
}

sub search {
    my %OPTS = @_;
    my %TRUEDOMAINS;
    if ( $OPTS{'truedomains_ref'} ) {
        %TRUEDOMAINS = %{ $OPTS{'truedomains_ref'} };
    }
    else {
        Cpanel::Config::LoadUserDomains::loadtrueuserdomains( \%TRUEDOMAINS, 1 );
    }
    my %OWNER;
    if ( $OPTS{'owner_ref'} ) {
        %OWNER = %{ $OPTS{'owner_ref'} };
    }
    else {
        Cpanel::Config::LoadUserOwners::loadtrueuserowners( \%OWNER, 1, 1 );
    }
    my $userplan_ref = Whostmgr::AcctInfo::Plans::loaduserplans();

    my $searchtype = $OPTS{'searchtype'};
    my $search     = $OPTS{'search'};       #avoid some IXHASH::Fetchs
    my $regex;

    if ( $search ne '' ) {
        eval { $regex = qr($search); };
        if ($@) {
            $regex = qr(\Q$search\E);
        }
    }

    my %ACCTS;
    my $can_see_all_accts = Whostmgr::ACLS::hasroot() || ( $ENV{'REMOTE_USER'} eq 'root' && Whostmgr::ACLS::checkacl('list-accts') );
    foreach my $user ( keys %TRUEDOMAINS ) {
        next if ( $user eq '' );
        if (  !$can_see_all_accts
            && $OWNER{$user} ne $ENV{'REMOTE_USER'} ) {
            delete $TRUEDOMAINS{$user};
            next();
        }
        my $domain = $TRUEDOMAINS{$user};

        if ( $search ne '' ) {
            if ( $searchtype eq 'domain' ) {
                if ( $domain !~ $regex ) { next; }
            }
            elsif ( $searchtype eq 'owner' ) {
                if ( $OWNER{$user} !~ $regex ) { next; }
            }
            elsif ( $searchtype eq 'user' ) {
                if ( $user !~ $regex ) { next; }
            }
            elsif ( $searchtype eq 'package' ) {
                if ( $userplan_ref->{$user} !~ $regex ) { next; }
            }
        }

        $ACCTS{$user} = 1;
    }
    return \%ACCTS;
}

1;
