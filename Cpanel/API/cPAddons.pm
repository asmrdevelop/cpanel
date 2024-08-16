package Cpanel::API::cPAddons;

# cpanel - Cpanel/API/cPAddons.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule      ();
use Cpanel::cPAddons::Class ();
use Cpanel::Server::Type    ();
use Cpanel::Exception       ();
use Cpanel::Imports;

sub _get_available_addons {
    _preflight();

    my $class_obj       = $Cpanel::cPAddons::Class::SINGLETON ||= Cpanel::cPAddons::Class->new();
    my %disabled_addons = $class_obj->get_disabled_addons();
    return [ map { !$disabled_addons{ $_->[0] } ? ( { 'module' => $_->[0], 'description' => $_->[1] } ) : () } ( $class_obj->load_cpaddon_feature_descs() ) ];
}

=head1 NAME

Cpanel::API::cPAddons

=head1 DESCRIPTION

UAPI functions related to cPAddons.

=head2 get_available_addons

=head3 Purpose

Return a list of available cPAddons

=head3 Arguments

  none

=head3 Returns

 [
  {
      name
      module
  },
  ....
 ]

=head3 Exceptions

generic exception

=cut

sub get_available_addons {
    my ( $args, $result ) = @_;
    $result->data( _get_available_addons() );
    return 1;
}

=head2 list_addon_instances

=head3 Purpose

Returns a list of deployed cPAddons instances for this account.

=head3 Arguments

=over

=item * addon - String - (Optional) If specified, limit the returned instances to the named addon
(in colon-delimited form). Otherwise, return all instances.

=back

=head3 Returns

An array (ref) of hash (refs), each of which has the following fields:

=over

=item - I<addon> - String - The name of the addon in colon-delimited form.

=item - I<installdir> - String - The full path of the directory in which the addon was deployed.

=item - I<instance> - String - The name of the instance, including the number suffix.

=item - I<unique_id> - String - A unique identifier for the addon that will stay the same even if the
addon settings change, but which will not stay the same if the same instance name is reused by a new
instance. This identifier is suitable for use in picking out an instance for modification.

=back

=head3 Exceptions

generic exception

=cut

sub list_addon_instances {
    my ( $args, $result ) = @_;

    _preflight();

    my $addon = $args->get('addon');

    Cpanel::LoadModule::load_perl_module('Cpanel::cPAddons::Instances');
    my $all_instances_info = Cpanel::cPAddons::Instances::get_instances($addon);

    if ( $all_instances_info->{error} ) {
        return 0;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::cPAddons::Util');
    my @instances;
    my @preserve = qw(addon installdir domain);
    for my $instance_name ( sort keys %{ $all_instances_info->{instances} } ) {
        my %new_info = map { $_ => $all_instances_info->{instances}{$instance_name}{$_} } @preserve;
        $new_info{instance}  = $instance_name;
        $new_info{unique_id} = Cpanel::cPAddons::Util::unique_instance_id(
            instance    => $instance_name,
            create_time => $all_instances_info->{instances}{$instance_name}{unix_time},
        );
        push @instances, \%new_info;
    }

    $result->data( \@instances );
    return 1;
}

=head2 get_instance_settings

=head3 Purpose

Given a unique id to select an instance, returns the settings related to that instance.

=head3 Arguments

=over

=item - I<unique_id> - String - The unique identifier of the addon instance as obtained from
the I<list_addon_instances> response.

=back

=head3 Returns

=over

=item - I<addon> - String - The name of the addon in colon-delimited form.

=item - I<admin_user> - String - The administrative user for the addon instance.

=item - I<autoupdate> - Boolean - Whether automatic updates are enabled for the addon instance.

=item - I<db_name> - String - The name of the database for the addon instance.

=item - I<db_type> - String - The type of database for the addon instance. This may be either 'mysql' or 'postgre'.

=item - I<db_user> - String - The database user for the addon instance.

=item - I<installdir> - String - The full path of the directory in which the addon was deployed.

=item - I<url_to_install> - String - The full URL to access the addon instance.

=back

=head3 Exceptions

generic exception

=cut

sub get_instance_settings {
    my ( $args, $result ) = @_;

    _preflight();

    my $unique_id = $args->get('unique_id');

    Cpanel::LoadModule::load_perl_module('Cpanel::cPAddons::Instances');
    my $instance_info = Cpanel::cPAddons::Instances::get_by_unique_id($unique_id);

    if ($instance_info) {
        my ( $db_type, $db_name, $db_user );
        for my $k ( sort keys %$instance_info ) {
            if ( $k =~ /^([^.]+)\.[^.]+\.sqldb$/ ) {    # e.g., mysql.wordpress.sqldb or postgre.e107.sqldb
                $db_type = $1;
                $db_name = $instance_info->{$k};
            }
            $db_user = $instance_info->{$k} if $k =~ /\.sqluser$/;
        }

        $result->data(
            {
                addon          => $instance_info->{addon},
                domain         => $instance_info->{domain},
                installdir     => $instance_info->{installdir},
                url_to_install => $instance_info->{url_to_install},
                admin_user     => $instance_info->{user},
                db_type        => $db_type,
                db_name        => $db_name,
                db_user        => $db_user,
                autoupdate     => $instance_info->{autoupdate},
            }
        );
        return 1;
    }

    $result->error( 'The system could not locate the “[_1]” instance.', $unique_id );
    return 0;
}

sub _preflight {
    if ( Cpanel::Server::Type::is_dnsonly() ) {
        die Cpanel::Exception::create( 'Unsupported', 'This function is disabled for [asis,DNSONLY] servers.' );
    }
    return;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    get_available_addons  => $allow_demo,
    list_addon_instances  => $allow_demo,
    get_instance_settings => $allow_demo,
);

1;
