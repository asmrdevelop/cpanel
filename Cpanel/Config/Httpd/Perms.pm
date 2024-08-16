package Cpanel::Config::Httpd::Perms;

# cpanel - Cpanel/Config/Httpd/Perms.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache::modules ();

use constant mailman_suexec_patch_version => '2.0';    # Everything is EA4 or CloudLinux now

=head1 NAME

Cpanel::Config::Httpd::Perms

=head1 DESCRIPTION

Utility module that checks if scripts run under the web server are executed as the user or as nobody/apache.

=head1 METHODS

=head2 Cpanel::Config::Httpd::Perms::webserver_runs_as_user()

Checks if various modules are installed that make scripts run as the user when called from the web server.

=head3 ARGUMENTS

=over 4

=item check

 - hash - with the following properties

=item check.itk

 - boolean - defaults to if not passed to preserve original behavior when called without arguments. - check if itk is running.

=item check.ruid2

 - boolean - defaults to checking if not passed to preserve original behavior when called without arguments. - check if ruid2 is running.

=item check.suexec

 - boolean - defaults to not checked if not passed - check if suexec is running.

=item check.suphp

 - boolean - defaults to not checked if not passed - check if suphp is running.

=back

=head3 RETURNS

boolean - 1 if the webserver runs script as the user, 0 otherwise.

=cut

sub webserver_runs_as_user {
    my %check = @_;
    %check = ( itk => 1, ruid2 => 1 ) if !%check;

    my ( $itk, $ruid2, $passenger, $suphp, $suexec ) = ( 0, 0, 0, 0, 0 );
    my $httpd_options = Cpanel::ConfigFiles::Apache::modules::get_options_support();

    # ITK for Apache 2.2 is an MPM.  ITK for Apache 2.4 is a loadable module
    if ( $check{itk} ) {
        $itk = 1 if $httpd_options->{'APACHE_MPM_DIR'} && $httpd_options->{'APACHE_MPM_DIR'} =~ m/itk/;    # Apache 2.2
        $itk = 1 if Cpanel::ConfigFiles::Apache::modules::is_supported('mpm_itk');                         # Apache 2.4
    }

    if ( $check{ruid2} ) {
        $ruid2 = 1 if Cpanel::ConfigFiles::Apache::modules::is_supported('mod_ruid2');
    }

    if ( $check{passenger} ) {
        $passenger = 1 if Cpanel::ConfigFiles::Apache::modules::is_supported('mod_passenger');
        $passenger = 1 if _alt_passenger_is_installed();
    }

    if ( $check{suphp} ) {
        my $suphp_supported = Cpanel::ConfigFiles::Apache::modules::is_supported('mod_suphp');

        my $handler = '';
        if ($suphp_supported) {
            require Cpanel::API;
            my $response = Cpanel::API::execute( 'LangPHP', 'php_get_domain_handler', { type => 'home' } );
            $handler = $response->{data}{php_handler};
        }

        $suphp = 1 if $handler eq 'suphp';
    }

    if ( $check{suexec} ) {
        $suexec = 1 if Cpanel::ConfigFiles::Apache::modules::is_supported('mod_suexec');
    }

    # If LSWS is running, always return 0. LSWS children run as nobody.
    return 0 if _lsws_is_running();
    return ( $itk || $ruid2 || $passenger || $suphp || $suexec );
}

sub _alt_passenger_is_installed {

    # Alt-passenger installs its files in another location
    # This file is created when alt-passenger is installed, removed upon uninstall
    return ( -e '/etc/profile.d/alt_mod_passenger.sh' ) ? 1 : 0;
}

sub _lsws_is_running {
    my $lswsctrl_path = '/usr/local/lsws/bin/lswsctrl';
    if ( -x $lswsctrl_path ) {
        require Cpanel::SafeRun::Errors;
        chomp( my $lsws_running = Cpanel::SafeRun::Errors::saferunnoerror( $lswsctrl_path, 'status' ) );
        if ( $lsws_running =~ m/^litespeed is running.*?$/ ) {
            return 1;
        }
    }

    return;
}

1;
