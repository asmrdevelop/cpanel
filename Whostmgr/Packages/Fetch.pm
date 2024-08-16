package Whostmgr::Packages::Fetch;

# cpanel - Whostmgr/Packages/Fetch.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Packages::Load ();
use Whostmgr::ACLS           ();
use Cpanel::Validate::Number ();

sub fetch_package_list {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    my $want        = $OPTS{'want'};                         #choices are creatable,editable,viewable,all
    my $package     = $OPTS{'package'};                      #Limit the list to a single package.
    my $reseller    = $ENV{'REMOTE_USER'};
    my $pkg_verbose = -e '/var/cpanel/pkgverbose' ? 1 : 0;

    my %PKG_PRIVS = ( 'can_view_all_pkgs' => 1, 'can_view_global_pkgs' => 1 );
    if ( $want ne 'all' && $want ne 'exists' && !Whostmgr::ACLS::hasroot() ) {

        # only load the reseller limits if they have limits as its currently pretty expensive to load all this up
        $PKG_PRIVS{'can_view_global_pkgs'} = Whostmgr::ACLS::checkacl('viewglobalpackages') ? 1 : 0;
        $PKG_PRIVS{'can_view_all_pkgs'}    = 0;
    }

    my $pkglist_ref = [];
    if ($package) {
        my $status_ref = {};
        Whostmgr::Packages::Load::load_package( $package, $status_ref );
        $pkglist_ref = [$package] if $status_ref->{'result'};
    }
    else {
        $pkglist_ref = _load_package_list();
    }

    # In this block we filter the pkglist_ref down to packages the reseller is allowed to see
    my %PKGS = %{ _find_packages_allowed_to_view( $want, $pkglist_ref, \%PKG_PRIVS, $reseller, $pkg_verbose ) };

    if ( $want eq 'editable' ) {
        my %PKGout;
        foreach my $pkg ( keys %PKGS ) {
            my $data = Whostmgr::Packages::Load::load_package($pkg);
            if ($data) {
                $PKGout{$pkg} = $data;
            }
        }
        return \%PKGout;
    }

    my $reseller_limits;

    if ( !Whostmgr::ACLS::hasroot() ) {
        require Whostmgr::Limits::Resellers;
        require Whostmgr::Limits::PackageLimits;
        $reseller_limits = Whostmgr::Limits::Resellers::load_resellers_limits();
        my $package_limits = Whostmgr::Limits::PackageLimits->load(0);

        if ( $reseller_limits->{'limits'}->{'preassigned_packages'}->{'enabled'} ) {
            delete @PKGS{ keys %PKGS };
        }

        my %INSTALLED_PKGS = map { $_ => 1 } @{$pkglist_ref};

        my $ar_pkg_names = $package_limits->list_packages();
        foreach my $pkg (@$ar_pkg_names) {
            if ( exists $INSTALLED_PKGS{$pkg} && $package_limits->create_for_reseller( $pkg, $reseller ) ) {
                $PKGS{$pkg} = 1;
            }
        }

        if ( $want eq 'creatable' ) {
            my @FORBIDDEN_PKGS;
            require Whostmgr::AcctInfo;
            my $plan_ref = Whostmgr::AcctInfo::acctamts($reseller);
            my %ACCTS    = $plan_ref ? %{$plan_ref} : ();             #make a copy as we might be modifying it below

            #ACCTS is the number of each plan the user has

            if ( $OPTS{'test_with_less_packages'} ) {

                # we use this for upgrading accounts
                my $package_to_subtract         = $OPTS{'test_with_less_packages'}->{'package'};
                my $num_of_packages_to_subtract = $OPTS{'test_with_less_packages'}->{'count'};

                # subtract here
                $ACCTS{$package_to_subtract} -= int $num_of_packages_to_subtract;
            }

            my %ACCOUNTLIST        = Whostmgr::AcctInfo::getaccts($reseller);
            my $number_of_accounts = scalar keys %ACCOUNTLIST;

            if ( $OPTS{'test_with_less_packages'} ) {
                $number_of_accounts -= $OPTS{'test_with_less_packages'}->{'count'};
            }

            foreach my $pkg ( keys %PKGS ) {

                # Specify which packages can be used for account creation and limit the amount of accounts created per package.
                if ( $reseller_limits->{'limits'}->{'number_of_packages'}->{'enabled'} ) {
                    my $limit_number_for_user = $package_limits->number_for_reseller( $pkg, $reseller );
                    if ( ( $ACCTS{$pkg} >= $limit_number_for_user ) && ( $limit_number_for_user !~ m/unlimited/i ) ) {
                        push @FORBIDDEN_PKGS, $pkg;
                        print qq{<!-- Package: [$pkg] skipped because number_of_packages : ($ACCTS{$pkg} >= $limit_number_for_user) && ($limit_number_for_user !~ /unlimited/i) -->\n} if $pkg_verbose;
                        next;
                    }
                }

                # Limit the total number of accounts that can be created.
                if ( $reseller_limits->{'limits'}->{'number_of_accounts'}->{'enabled'} && $number_of_accounts >= $reseller_limits->{'limits'}->{'number_of_accounts'}->{'accounts'} ) {
                    if ( $OPTS{'skip_number_of_accounts_limit'} ) {
                        print qq(<!-- Package: [$pkg] was not skipped because flag \$OPTS{'skip_number_of_accounts_limit'} is set -->\n) if $pkg_verbose;
                        next;
                    }
                    push @FORBIDDEN_PKGS, $pkg;
                    print qq{<!-- Package: [$pkg] skipped because number_of_accounts is at or exceeded -->\n} if $pkg_verbose;
                    next;
                }
            }
            foreach my $pkg (@FORBIDDEN_PKGS) {
                delete $PKGS{$pkg};
            }
        }
    }

    return \%PKGS if $want eq 'exists';

    %PKGS = map { @$_ } grep { defined $_->[1] } map { [ $_ => Whostmgr::Packages::Load::load_package($_) ] } keys %PKGS;

    if ( !Whostmgr::ACLS::hasroot() && $want eq 'creatable' && $reseller_limits->{'limits'}->{'resources'}->{'enabled'} ) {
        my @FORBIDDEN_PKGS;
        my %RSUSED;
        my %RSREMAIN;

        my $skipuser = $OPTS{'test_without_user'}->{'user'} || '';

        require Whostmgr::Resellers::Stat;
        my ( $totaldiskused, $totalbwused, $totaldiskalloc, $totalbwalloc ) = Whostmgr::Resellers::Stat::statres( 0, $skipuser, 'res' => $reseller, 'skip_cache' => 1 );

        if ( $reseller_limits->{'limits'}->{'resources'}->{'overselling'}->{'type'}->{'bw'} ) {
            $RSUSED{'bw'} = $totalbwused;
        }
        else {
            $RSUSED{'bw'} = $totalbwalloc;
        }
        if ( $reseller_limits->{'limits'}->{'resources'}->{'overselling'}->{'type'}->{'disk'} ) {
            $RSUSED{'disk'} = $totaldiskused;
        }
        else {
            $RSUSED{'disk'} = $totaldiskalloc;
        }

        my $reseller_disk_limit = $reseller_limits->{'limits'}->{'resources'}->{'type'}->{'disk'} // 0;
        my $reseller_bw_limit   = $reseller_limits->{'limits'}->{'resources'}->{'type'}->{'bw'}   // 0;
        $reseller_disk_limit = 0 unless _is_valid_number_for_resource( $reseller_limits->{'limits'}->{'resources'}->{'type'}->{'disk'}, $pkg_verbose );
        $reseller_bw_limit   = 0 unless _is_valid_number_for_resource( $reseller_limits->{'limits'}->{'resources'}->{'type'}->{'bw'},   $pkg_verbose );

        $RSREMAIN{'disk'} = $reseller_disk_limit - ( $RSUSED{'disk'} // 0 );
        $RSREMAIN{'bw'}   = $reseller_bw_limit -   ( $RSUSED{'bw'}   // 0 );

        foreach my $pkg ( keys %PKGS ) {
            my $bwlimit = $PKGS{$pkg}->{'BWLIMIT'} // 0;
            my $quota   = $PKGS{$pkg}->{'QUOTA'}   // 0;

            if ( $bwlimit eq 'unlimited' || int($bwlimit) < 1 ) {
                push @FORBIDDEN_PKGS, $pkg;
                print qq{<!-- Package: [$pkg] Sorry, you cannot create an account with an unlimited bandwidth limits. -->\n} if $pkg_verbose;
                next();
            }
            if ( $quota eq 'unlimited' || int($quota) < 1 ) {
                push @FORBIDDEN_PKGS, $pkg;
                print qq{<!-- Package: [$pkg] Sorry, you cannot create an account with an unlimited quota. -->\n} if $pkg_verbose;
                next();
            }
            if ( $reseller_limits->{'limits'}->{'resources'}->{'overselling'}->{'type'}->{'disk'} ) {
                if ( $RSREMAIN{'disk'} < 1 ) {
                    push @FORBIDDEN_PKGS, $pkg;
                    print qq{<!-- Package: [$pkg] Sorry you cannot create this account because you are out of disk space. You have exceeded your disk space allotment by (} . $RSREMAIN{'disk'} . qq{Megabytes! -->\n} if $pkg_verbose;
                    next();
                }
            }
            else {
                if ( $RSREMAIN{'disk'} < $quota ) {
                    my $ret = "Sorry you cannot create this account because you are out of disk space. ";
                    if ( $RSREMAIN{'disk'} > 0 ) {
                        $ret .= " You only have $RSREMAIN{'disk'} Megabytes remaining, and this account requires ${quota}.\n";
                    }
                    else {
                        my $absdisk = abs( $RSREMAIN{'disk'} );
                        $ret .= " You have exceeded your disk space allotment by ${quota} Megabytes!\n";
                    }
                    push @FORBIDDEN_PKGS, $pkg;
                    print qq{<!-- Package: [$pkg] $ret -->\n} if $pkg_verbose;
                    next();
                }
            }

            if (   ( $RSREMAIN{'bw'} < $bwlimit && !( $reseller_limits->{'limits'}->{'resources'}->{'overselling'}->{'type'}->{'bw'} ) )
                || ( $RSREMAIN{'bw'} < 0 && $reseller_limits->{'limits'}->{'resources'}->{'overselling'}->{'type'}->{'bw'} ) ) {
                my $ret = "Sorry you cannot create this account because this would exceed your allotted bandwidth. ";
                if ( $RSREMAIN{'bw'} > 0 ) {
                    $ret .= "You only have $RSREMAIN{'bw'} Megabytes remaining, and this account package requires ${bwlimit} Megabytes.\n";
                }
                else {
                    my $absbw = abs( $RSREMAIN{'bw'} );
                    $ret .= " You have exceeded your bandwidth allotment by $absbw Megabytes!\n";
                }
                push @FORBIDDEN_PKGS, $pkg;
                print qq{<!-- Package: [$pkg] $ret -->\n} if $pkg_verbose;
                next();
            }
        }
        foreach my $pkg (@FORBIDDEN_PKGS) {
            delete $PKGS{$pkg};
        }
    }

    return \%PKGS;
}

sub _find_packages_allowed_to_view {
    my ( $want, $pkglist_ref, $pkg_privs_hr, $reseller, $pkg_verbose ) = @_;

    my %PKGS;
    if ( $pkg_privs_hr->{'can_view_all_pkgs'} ) {
        %PKGS = map { $_ => 1 } @{$pkglist_ref};    # we can view all packages if this is set.  no filtering
    }
    else {
        %PKGS = map { $_ => 1 } grep( /^\Q$reseller\E_/, @{$pkglist_ref} );    # we can always view our owned packages
        if ( $pkg_privs_hr->{'can_view_global_pkgs'} && $want ne 'editable' ) {
            print "<!-- can_view_global_pkgs is set -->\n" if $pkg_verbose;
            foreach ( grep( !/_/, @{$pkglist_ref} ) ) {                        # packages without "_" are global packages
                $PKGS{$_} = 1;
            }
        }
    }

    return \%PKGS;
}

sub _load_package_list {
    my @FS = qw/default/;

    my $package_dir = Whostmgr::Packages::Load::package_dir();
    $package_dir =~ s{/$}{};

    # If root, try to mkdir on package_dir()
    if ( !-d $package_dir && $> == 0 ) {
        unlink $package_dir;    # Just in case it's a file.
        mkdir $package_dir, 0700;
    }

    if ( opendir my $pkgdir_fh, $package_dir ) {
        push @FS, grep { !( -d "$package_dir/$_" ) } readdir $pkgdir_fh;
        closedir $pkgdir_fh;
    }
    return \@FS;
}

sub _is_valid_number_for_resource {
    my ( $item, $verbose ) = @_;

    return 0 unless $item;

    my $is_valid;
    eval {
        Cpanel::Validate::Number::rational_number($item);
        $is_valid = 1;
        1;
    } or do {
        print qq{<!-- Error: Invalid number used for reseller resource limit -->\n} if $verbose;
        $is_valid = 0;
    };
    return $is_valid;
}

1;
