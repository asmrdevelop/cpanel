package Cpanel::ConfigFiles::Apache::passenger;

# cpanel - Cpanel/ConfigFiles/Apache/passenger.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

=head1 NAME

Cpanel::ConfigFiles::Apache::passenger - Manage apache configurations for Passenger applications

=head1 SYNOPSIS

    use Cpanel::ConfigFiles::Apache::passenger;

    Cpanel::ConfigFiles::Apache::passenger::generate_apache_conf_for_app( 'user', { 'domain' => 'example.com', 'name' => 'myapp' } );
    Cpanel::ConfigFiles::Apache::passenger::remove_apache_conf_for_app( 'user', 'example.com', 'myapp' );

=head1 DESCRIPTION

This module encapsulates the logic to create and remove apache configurations for a Passenger application.
You should prefer the C<remove_apache_conf> and C<generate_apache_conf> methods in the C<Cpanel::Config::userdata::PassengerApps> module,
which invoke the methods in this module.

=cut

use File::Spec ();

use Cpanel::ConfigFiles::Apache::vhost ();
use Cpanel::ConfigFiles::Apache        ();
use Cpanel::Config::userdata::Load     ();
use Cpanel::Exception                  ();
use Cpanel::LoadFile                   ();
use Cpanel::LoadModule                 ();
use Cpanel::Template                   ();

=head1 METHODS

=head2 generate_apache_conf_for_app($user, $app_data_hr)

Creates an apache configuration file for the provided user and application data.

=over 3

=item C<< $user >> [in]

A string representing a username.

=item C<< $app_data_hr >> [in]

A hashref representing the data of a Passenger application.
See L<Cpanel::Config::userdata::PassengerApps::register_application>.

=back

B<Returns>: On failure, throws an exception. On success, returns B<1>.

=cut

sub generate_apache_conf_for_app {
    my ( $user, $app_config_hr ) = @_;

    my $msg_sr        = _process_template( $user, $app_config_hr );
    my $conf_files_ar = _find_apache_paths_for_app( $user, $app_config_hr->{'domain'}, $app_config_hr->{'name'} );

    foreach my $path ( @{$conf_files_ar} ) {
        my $temp_path = $path . ".tmp";
        if ( open my $fh, '>', $temp_path ) {
            print {$fh} ${$msg_sr};
            close $fh;

            require Cpanel::ConfigFiles::Apache::Syntax;
            my $res = Cpanel::ConfigFiles::Apache::Syntax::check_syntax($temp_path);
            if ( !$res->{status} ) {
                unlink $temp_path;
                die Cpanel::Exception->create( 'The system failed to generate the [asis,Apache] configuration file due to the following error: [_1]', [ $res->{message} ] );
            }
            rename $temp_path, $path;
        }
    }

    Cpanel::ConfigFiles::Apache::vhost::update_domains_vhosts( $app_config_hr->{'domain'} );

    return 1;
}

=head2 remove_apache_conf_for_app($user, $domain, $app_name)

Removes an apache configuration file for the provided user, domain, and Passenger app name.

=over 3

=item C<< $user >> [in]

A string representing a username.

=item C<< $domain >> [in]

A string representing the domain where the Passenger application lives.

=item C<< $app_name >> [in]

A string representing the name of a Passenger application.

=item C<< $force >> [in, optional]

A boolean indicating if we should force removal of the ssl and std configs.

=back

B<Returns>: On failure, throws an exception. On success, returns B<1>.

=cut

sub remove_apache_conf_for_app {
    my ( $user, $domain, $app_name, $force ) = @_;

    my $conf_files_ar = _find_apache_paths_for_app( $user, $domain, $app_name, $force );

    foreach my $path ( @{$conf_files_ar} ) {
        unlink $path if -e $path;
    }

    Cpanel::ConfigFiles::Apache::vhost::update_domains_vhosts($domain);

    return 1;
}

sub _process_template {
    my ( $user, $data_hr ) = @_;

    my $ext = 'default';

    my $sanitized_envvars;
    if ( 'HASH' eq ref $data_hr->{'envvars'} && scalar keys %{ $data_hr->{'envvars'} } ) {
        foreach my $env_name ( keys %{ $data_hr->{'envvars'} } ) {
            my $env_data = $data_hr->{'envvars'}->{$env_name};
            $env_data =~ s/(["\\])/\\$1/g;
            $sanitized_envvars->{$env_name} = $env_data;
        }
    }

    if ( -r _passenger_apps_template_file('local') ) {
        $ext = 'local';
    }

    my ( $rc, $msg_sr ) = Cpanel::Template::process_template(
        'apache',
        {
            'data' => {
                ( map { $_ => $data_hr->{$_} } grep { $_ ne 'envvars' } keys %{$data_hr} ),
                'cpuser'  => $user,
                'envvars' => $sanitized_envvars
            },
            'template_file' => _passenger_apps_template_file($ext),
            'includes'      => {},
        },
        {},
    );
    die Cpanel::Exception->create( 'The system failed to generate the [asis,Apache] configuration file due to the following error: [_1]', [$msg_sr] )
      if !$rc;

    return $msg_sr;
}

sub _find_apache_paths_for_app {
    my ( $user, $domain, $app_name, $force ) = @_;

    $force //= 0;

    my @paths;
    my @types = qw(std);
    push @types, 'ssl' if $force || Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $domain );

    foreach my $type (@types) {
        my $include_path = File::Spec->catdir( Cpanel::ConfigFiles::Apache->new()->dir_conf_userdata(), "/$type/2_4/$user/$domain/" );

        if ( !-e $include_path ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
            Cpanel::SafeDir::MK::safemkdir($include_path);
        }

        push @paths, File::Spec->catfile( $include_path, $app_name . '.conf' );
    }

    return \@paths;
}

# Default template is shipped as part of the mod_passenger rpm
sub _passenger_apps_template_file {
    my $ext = shift;

    # This bit is defined in the “Passenger w/ Multiple Ruby” design document
    my $path    = Cpanel::LoadFile::load_if_exists("/etc/cpanel/ea4/passenger.ruby") || "";
    my $rubyver = substr( $path, -2, 2 );
    if ( $rubyver !~ m/[1-9][0-9]/ ) {
        $rubyver = "-system";
    }

    my $version_specific = "/var/cpanel/templates/apache2_4/ruby$rubyver-mod_passenger.appconf.$ext";
    return $version_specific if length $rubyver && -f $version_specific;

    return "/var/cpanel/templates/apache2_4/passenger_apps.$ext";    # ambiguous legacy name from older ULC
}

1;
