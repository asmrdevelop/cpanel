
# cpanel - Cpanel/cPAddons/Instances.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Instances;

use strict;
use warnings;

use Cpanel::Imports;

use Cpanel                    ();
use Cpanel::cPAddons::Cache   ();
use Cpanel::cPAddons::Notices ();
use Cpanel::cPAddons::Util    ();
use Cpanel::Encoder::Tiny     ();
use Cpanel::PwCache           ();
use Cpanel::Locale            ();

=head1 NAME

Cpanel::cPAddons::Instances

=head1 DESCRIPTION

Module for listing and managing deployed instances of addons under users' public_html directories.

=head1 FUNCTIONS

=head2 ensure_prerequisites(USER, HOMEDIR)

Given a username USER and a home directory HOMEDIR, ensure that the expected directories exist.

B<Important>: This function must not be run as root. Doing so would facilitate symlink attacks.

Returns an error string on failure and an empty list on success.

=cut

sub ensure_prerequisites {
    my ( $user, $homedir ) = @_;
    my $error;

    Cpanel::cPAddons::Util::must_not_be_root('Writes to homedir without dropping privileges');

    if ( !-d "$homedir/.cpaddons/" ) {
        if ( !mkdir "$homedir/.cpaddons/" ) {
            my $exception = $!;
            logger()->warn("Unable to create user .cpaddons directory for $user: $!");
            $error = locale()->maketext(
                'The system could not create user’s [_1] directory for [_2]: [_3]',
                '.cpaddons',
                Cpanel::Encoder::Tiny::safe_html_encode_str($user),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception)
            );
            Cpanel::cPAddons::Notices::singleton()->add_critical_error($error);
            return $error;
        }
    }

    if ( !-d "$homedir/.cpaddons/moderation/" ) {
        if ( !mkdir "$homedir/.cpaddons/moderation/" ) {
            my $exception = $!;
            logger()->warn("Unable to create user .cpaddons/moderation directory for $user: $!");
            $error = locale()->maketext(
                'The system could not create user’s [_1] directory for [_2]: [_3]',
                '.cpaddons/moderation',
                Cpanel::Encoder::Tiny::safe_html_encode_str($user),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            );
            Cpanel::cPAddons::Notices::singleton()->add_critical_error($error);
            return $error;
        }
    }

    return;
}

=head2 get_instances(MODULE)

Get a list of deployed instances under the current user's home directory.

=head3 Arguments

- MODULE - String - The cPAddons module name. See the MODULE NAMES section of B<perldoc Cpanel::cPAddons::Module> for more info.

=head3 Returns

A hash ref containing:

- user - The name of the current user.

- instances - Hash ref - A mapping of YAML file names to YAML file contents representing the individual instances.

- error - String - (Only on failure) An error message explaining the failure.

=cut

sub get_instances {
    my ($module) = @_;

    Cpanel::cPAddons::Util::must_not_be_root('Calls ensure_prerequisites, which writes to homedir without dropping privileges');

    my @PW      = Cpanel::PwCache::getpwuid($>);
    my $user    = $PW[0];
    my $homedir = $PW[7];

    my $response = {
        user => $user,
    };

    if ( $response->{error} = ensure_prerequisites( $user, $homedir ) ) {
        return $response;
    }

    my $instances = {};

    if ( opendir my $ao_dh, "$homedir/.cpaddons/" ) {
        for my $module_file_name ( readdir $ao_dh ) {
            $module_file_name =~ s{ ^ ( [^.]  .*? \. \d+ ) \.yaml $ }{$1}x or next;

            next if $module && $module_file_name !~ m/^\Q$module\E\.\d+$/;

            $instances->{$module_file_name} = {};
            my $module_instance_path = "$Cpanel::homedir/.cpaddons/$module_file_name";
            if (
                !Cpanel::cPAddons::Cache::read_cache(    # drops privileges when passed a user
                    $module_instance_path,
                    $instances->{$module_file_name},
                    $user
                )
            ) {
                delete $instances->{$module_file_name};
                next;
            }
        }
        close $ao_dh;
        $response->{instances} = $instances;
    }
    else {
        my $exception = $!;
        logger()->warn("Unable to read .cpaddons directory for $user: $!");
        $response->{error} = locale()->maketext(
            'The system could not access the [asis,cPanel] account user’s [_1] directory for [_2]: [_3]',
            '.cpaddons',
            Cpanel::Encoder::Tiny::safe_html_encode_str($user),
            Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
        );
        Cpanel::cPAddons::Notices::singleton()->add_critical_error( $response->{error} );
    }

    return $response;
}

=head2 get_instances_with_sort(MODULE, USER)

Same as get_instances, but sorts the instances by deployment URL before returning them.

=cut

sub get_instances_with_sort {
    my ( $module, $user ) = @_;

    my $response = get_instances( $module, $user );
    return $response if $response->{error};

    my @instances;

    # Convert to a list
    foreach my $instance_name ( keys %{ $response->{instances} } ) {
        my $install = $response->{instances}{$instance_name};
        $install->{install_filename} = $instance_name;
        push @instances, $install;
    }

    # Sort them so they are in a sensible order
    my @sorted_instances = sort { ( $a->{url_to_install} || '' ) cmp( $b->{url_to_install} || '' ) } @instances;

    $response->{sorted_instances} = \@sorted_instances;
    return $response;
}

=head2 get_by_unique_id(UNIQUE_ID)

Looks up a single instance by unique id.

=head3 Arguments

UNIQUE_ID - String - The unique id for an instance. See documentation for UAPI cPAddons::list_addon_instances
Cpanel::cPAddons::Util::unique_instance_id() for more info on this.

=head3 Returns

If an instance with the given id is found, it will be returned. Otherwise, the function returns
undef.

=cut

sub get_by_unique_id {
    my ($unique_id) = @_;

    my $all_instances_info = get_instances();

    my $instance_info;
    for my $instance_name ( sort keys %{ $all_instances_info->{instances} } ) {
        my $this_instance_unique_id = Cpanel::cPAddons::Util::unique_instance_id(
            instance    => $instance_name,
            create_time => $all_instances_info->{instances}{$instance_name}{unix_time},
        );

        if ( $this_instance_unique_id eq $unique_id ) {
            $instance_info = $all_instances_info->{instances}{$instance_name};
            last;
        }
    }

    return $instance_info;    # undef ok (caller must check)
}

=head2 Cpanel::cPAddons::Instances::get_instance()

Fetch a single instance based on its configuration file name.

=head3 ARGUMENTS

=over

=item module_file_name - string - name of the instances configuration file.

=back

=head3 RETURNS

hash ref - containing the configuration for the instances

=cut

sub get_instance {
    my $module_file_name = shift;

    Cpanel::cPAddons::Util::must_not_be_root('Calls ensure_prerequisites, which writes to homedir without dropping privileges');

    my @PW      = Cpanel::PwCache::getpwuid($>);
    my $user    = $PW[0];
    my $homedir = $PW[7];

    if ( ensure_prerequisites( $user, $homedir ) ) {
        return;
    }

    my $module_instance_path = "$homedir/.cpaddons/$module_file_name";

    my $instance = {};
    return $instance if Cpanel::cPAddons::Cache::read_cache(    # drops privileges when passed a user
        $module_instance_path,
        $instance,
        $user
    );
    return;
}

1;
