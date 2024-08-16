package Whostmgr::Accounts::Unsuspend::Htaccess;

# cpanel - Whostmgr/Accounts/Unsuspend/Htaccess.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::WebVhosts            ();
use Cpanel::Config::userdata::Load       ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::FileUtils::Lines             ();
use Cpanel::SafeDir::Read                ();

sub _get_domain_docroot {
    my ( $domain, $user, $wvh, $vhost_done_hr ) = @_;

    my $vhost_name = $wvh->get_vhost_name_for_domain($domain) or do {
        warn "“$domain” does not have a web vhost!\n";
        return;
    };

    return if $vhost_done_hr->{$vhost_name};

    $vhost_done_hr->{$vhost_name} = 1;

    my $vh_conf = Cpanel::Config::userdata::Load::load_userdata_domain( $user, $vhost_name );
    if ( !$vh_conf || !%$vh_conf ) {
        warn "Failed to load vhost config data for “$user”’s web vhost “$vhost_name”!\n";
        return;
    }

    return $vh_conf->{'documentroot'} || do {
        warn "Vhost config data for “$user”’s web vhost “$vhost_name” has no document root!\n";
        undef;
    };
}

sub unsuspend_htaccess {
    my ( $user, $domains ) = @_;

    my $wvh = Cpanel::Config::WebVhosts->load($user);

    my %vhost_done;

    return Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            for my $domain (@$domains) {
                my $docroot = _get_domain_docroot( $domain, $user, $wvh, \%vhost_done );

                next if !$docroot;

                my $htaccess_path = "$docroot/.htaccess";

                if ( -e $htaccess_path && Cpanel::FileUtils::Lines::has_txt_in_file( $docroot . '/.htaccess', '^RedirectMatch\s.+suspended.?page' ) ) {
                    unlink $htaccess_path or warn "Failed to unlink “$htaccess_path”: $!.";
                }

                if ( my $htaccess_suspend_file = _get_htaccess_suspend_file($docroot) ) {

                    #needed for taint-mode
                    ($htaccess_suspend_file) = ($htaccess_suspend_file) =~ /^(\.htaccess\.suspend(?:\.?[0-9]+)?)$/;

                    my $suspend_file_path = "$docroot/$htaccess_suspend_file";

                    if ( -z $suspend_file_path ) {
                        unlink $suspend_file_path or warn "Failed to unlink “$suspend_file_path”: $!.";
                    }
                    else {
                        unlink $docroot . '/.htaccess' if ( -e _ );
                        rename $suspend_file_path, $htaccess_path or warn "Failed to rename “$suspend_file_path” to “$htaccess_path”: $!.";
                    }
                }
            }

            return 1;
        },
        $user
    );

}

sub _get_htaccess_suspend_file {
    my ($docroot) = @_;

    my $checkref = sub {
        my ($file) = @_;
        if ( $file =~ /^\.htaccess\.suspend/ ) {
            return 1;
        }
        return;
    };

    my $newest_htaccess_file;
    my $time = 0;
    foreach my $htaccess_file ( Cpanel::SafeDir::Read::read_dir( $docroot, $checkref ) ) {
        if ( $htaccess_file =~ /^\.htaccess\.suspend\.([0-9]+)$/ ) {
            if ( $1 > $time ) {
                $newest_htaccess_file = $htaccess_file;
                $time                 = $1;
            }
        }
        elsif ( !defined $newest_htaccess_file && $htaccess_file eq '.htaccess.suspend' ) {
            $time                 = 1;
            $newest_htaccess_file = $htaccess_file;
        }
    }

    # should return the full path
    return $newest_htaccess_file;
}

1;
