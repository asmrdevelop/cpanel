
# cpanel - Cpanel/EA4/Install.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::EA4::Install;

use cPstrict;

use Cpanel::OS                        ();
use Cpanel::Mkdir                     ();
use Cpanel::SysPkgs                   ();
use Cpanel::Pkgr                      ();
use Cpanel::EA4::Constants            ();
use Cpanel::HTTP::Tiny::FastSSLVerify ();
use Cpanel::Yum::Vars                 ();

use File::Temp ();

use constant _ENOENT => 2;

=head1 NAME

Cpanel::EA4::Install

=head1 DESCRIPTION

Due to needing the universal-hooks package pretty much all the time, this was sectioned out of scripts/cpanel_initial_install.
It's used during said script, and during scripts/maintenance to ensure the same.

=head1 SYNOPSIS

    use Cpanel::EA4::Install;

    if (!Cpanel::EA4::Install::ea4_repo_already_installed()) {
        Cpanel::EA4::Install::install_ea4_repo();
    }


=head1 SUBROUTINES

=head2 ea4_repo_already_installed()

Takes no arguments. Returns true if ea4 package repos exist, false otherwise.

=head2 install_ea4_repo(%options)

Does the necessary actions to ensure the proper EA4 repository is available for your system.

=head3 Input Options Hash:

=over 4

=item B<log_info> - CODE, callback for logging informational messages.  Provides one argument, the message.

    Defaults to sub { print shift }

=item B<log_error> - CODE, callback for logging error messsages. Provides one argument, the message.

    Defaults to sub { warn shift }

=item B<skip_repo_setup> - BOOL, short circuits immediately.  Note: It's not clear why this isn't just up to the caller to check.

=back

=head3 Output

BOOL describing whether the action overall succeeded or failed.

Should not throw exceptions.

=cut

sub install_ea4_repo (%options) {

    return if $options{skip_repo_setup};
    return if -e '/etc/apachedisable';

    # Allow callers to provide their own logging & running routines
    $options{log_error} //= sub { warn shift };
    $options{log_info}  //= sub { say shift };

    $options{log_info}->("ea4: setup yum vars");
    Cpanel::Yum::Vars::install();

    my $syspkg = Cpanel::SysPkgs->new();
    $syspkg->ensure_plugins_turned_on();

    if ( Cpanel::OS::ea4_install_bare_repo() ) {

        if ( !$options{skip_gpg_key} ) {
            $options{log_info}->("ea4: installing public key");

            Cpanel::Mkdir::ensure_directory_existence_and_mode( $Cpanel::EA4::Constants::ea4_dir, 0755 );

            if ( my $err = _load_io_socket_ssl_or_return_error() ) {
                $options{log_error}->("Could not download the public key from “$Cpanel::EA4::Constants::public_key_url”: IO::Socket::SSL unavailable: $err");
                return 0;
            }
            else {
                my $http     = Cpanel::HTTP::Tiny::FastSSLVerify->new();
                my $response = $http->mirror( $Cpanel::EA4::Constants::public_key_url, $Cpanel::EA4::Constants::public_key_path );
                if ( !$response->{success} ) {
                    $options{log_error}->("Could not download the public key from “$Cpanel::EA4::Constants::public_key_url”: $response->{status} $response->{reason}: $response->{content}");
                    return 0;

                }
                my $imported = $syspkg->add_repo_key($Cpanel::EA4::Constants::public_key_path);
                return 0 if !$imported;
            }
        }

        $options{log_info}->("  - ea4: installing package repository config");

        if ( -f Cpanel::OS::ea4_from_bare_repo_path() && !-z _ ) {
            $options{log_info}->("ea4: package repo is already installed");
        }
        else {
            my $opts = $syspkg->get_repo_details('EA4');
            my $res  = $syspkg->add_repo(%$opts);
            if ( !$res->{success} ) {
                my $status = $res->{status} // 'Unknown status';
                my $reason = $res->{reason} // 'Unknown reason';
                $options{log_error}->("Could not install EA4 package repo: $status $reason");
                return 0;
            }
        }
    }

    if ( Cpanel::OS::ea4_install_repo_from_package() ) {
        my $cl_pkg_url = Cpanel::OS::ea4_from_pkg_url();
        my $pkg        = Cpanel::OS::ea4_from_pkg_reponame();

        $options{log_info}->( "ea4: installing " . Cpanel::OS::display_name() . " public key and EA4 package from the “$pkg” package" );

        if ( Cpanel::Pkgr::get_package_version($pkg) ) {
            $options{log_info}->("ea4: “$pkg” is already installed");
        }
        else {
            my $url_name = $cl_pkg_url;
            $url_name =~ s{.*/([^/]+)$}{$1};
            my $http     = Cpanel::HTTP::Tiny::FastSSLVerify->new();
            my $response = $http->mirror( $cl_pkg_url, $url_name );
            if ( !$response->{success} ) {
                $options{log_error}->( "Could not download “$cl_pkg_url”: " . join( ' ', map { $response->{$_} // '' } qw{ status reason } ) );
                return 0;
            }

            eval { $syspkg->install_packages( packages => [$url_name] ) };
            if ($@) {
                $options{log_error}->("Could not install “$url_name”: $@");
                return 0;
            }

            unlink $url_name;    # try not to leave cruft
        }
    }

    return 1;
}

sub ea4_repo_already_installed() {

    if ( Cpanel::OS::ea4_install_repo_from_package() ) {

        my $pkg = Cpanel::OS::ea4_from_pkg_reponame();

        if ( !defined $pkg ) {
            die q[ea4_from_pkg_reponame is not defined for the current distro ] . Cpanel::OS::display_name();
        }

        return 0 unless Cpanel::Pkgr::is_installed($pkg);
    }

    if ( Cpanel::OS::ea4_install_bare_repo() ) {
        my $local_repo_file = Cpanel::OS::ea4_from_bare_repo_path();

        if ( !defined $local_repo_file ) {
            die q[ea4_from_bare_repo_path is not defined for the current distro ] . Cpanel::OS::display_name();
        }

        return 0 unless $local_repo_file && -f $local_repo_file;
    }

    return 1;
}

sub _load_io_socket_ssl_or_return_error() {
    local $@;
    eval { require IO::Socket::SSL; };
    return $@;
}

1;
