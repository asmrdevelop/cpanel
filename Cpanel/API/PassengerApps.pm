package Cpanel::API::PassengerApps;

# cpanel - Cpanel/API/PassengerApps.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::API::PassengerApps

=head1 SYNOPSIS

    use Cpanel::API::PassengerApps ();

    my ($cpanel_args, $cpanel_result);
    my $status = Cpanel::API::PassengerApps::register_application($cpanel_args, $cpanel_result);

=head1 DESCRIPTION

UAPI calls to manage a cPanel user's Passenger applications

=cut

our $VERSION = '1.0';
use Try::Tiny;

use Cpanel::Exception      ();
use Cpanel::AdminBin::Call ();
use Cpanel::PwCache        ();
use Cpanel::JSON           ();
use Cpanel::LoadFile       ();

my $allow_demo = { allow_demo => 1 };

our %API = (
    _needs_role       => 'WebServer',
    _needs_feature    => 'passengerapps',
    list_applications => $allow_demo,
);

=head1 SUBROUTINES

=head2 register_application()

=head3 Purpose

Register a new Passenger application for the user

=head3 Arguments

See documentation for the C<register_application()> method in L<Cpanel::Config::userdata::PassengerApps>

=head3 Output

The full configuration for the newly created Passenger application

    {
        "deployment_mode" => "production",
        "base_uri"        => "/redmine",
        "path"            => "/home/cptest/redmine",
        "name"            => "redmine",
        "domain"          => "cptest.tld",
        "enabled"         => "1",
        "envvars"         => { "one" => "1" }
    }

=cut

sub register_application {
    my ( $args, $result ) = @_;

    my $config_hr;
    $config_hr->@{qw(name path domain)} = $args->get_length_required(qw(name path domain));

    # optional parameters
    $config_hr->@{qw(deployment_mode enabled base_uri)} = $args->get(qw(deployment_mode enabled base_uri));
    _populate_envvars( $config_hr, $args );

    my $app_config = _call_adminbin( 'REGISTER_APPLICATION', [$config_hr] );
    $result->data($app_config);

    return 1;
}

=head2 list_applications()

=head3 Purpose

List the Passenger applications configured on the cPanel account

See documentation for the C<list_applications()> method in L<Cpanel::Config::userdata::PassengerApps>

=head3 Arguments

None.

=head3 Output

An array containing details for each application configured on the cPanel account

    [
        ...
        {
            "deployment_mode" => "production",
            "base_uri"        => "/redmine",
            "path"            => "/home/cptest/redmine",
            "name"            => "redmine",
            "domain"          => "cptest.tld",
            "enabled"         => "1",
            "envvars"         => { "one" => "1" }
        },
        ...
    ]

=cut

my %dep_types = (
    npm => 1,
    pip => 1,
    gem => 1,
);

sub _get_versioned {
    my ( $val, $from, $to ) = @_;

    $val =~ s{/\Q$from\E([^/]*)$}{/\Q$to\E$1}i;
    my $version_part = $1;

    if ( !-x $val && length($version_part) ) {
        for ( 0 .. length($version_part) - 1 ) {
            $val = substr( $val, 0, length($val) - 1, "" );
            last if -x $val;
        }
    }
    $val = $to if !-x $val;

    return $val;
}

sub _get_dep_info_for_app {
    my ($app) = @_;

    my $bundler = $app->{ruby} || Cpanel::LoadFile::load_if_exists("/etc/cpanel/ea4/passenger.ruby");
    my $origval = $bundler;

    if ($bundler) {
        if ( $bundler =~ m/ea-ruby/ ) {
            $bundler =~ s{/[^/]+$}{/../bin/bundler};

            if ( !-e $bundler ) {
                $bundler =~ s{/bin/bundler$}{/local/bin/bundler};
                if ( !-e $bundler ) {
                    warn "Could not find bundler based on “$origval”.\n";
                    $bundler = "bundler";
                }
            }
        }
        else {
            $bundler = _get_versioned( $bundler, ruby => "bundler" );
        }
    }
    else {
        $bundler = "bundler";
    }

    my $pip = $app->{python} || Cpanel::LoadFile::load_if_exists("/etc/cpanel/ea4/passenger.python") || "pip";
    $pip = _get_versioned( $pip, python => "pip" );

    my $npm = $app->{nodejs} || Cpanel::LoadFile::load_if_exists("/etc/cpanel/ea4/passenger.nodejs") || "npm";
    $npm = _get_versioned( $npm, node => "npm" );

    return {
        npm => {
            file => "package.json",
            cmd  => [ $npm, "install" ],
        },
        pip => {
            file => "requirements.txt",
            cmd  => [ $pip, qw( install --user -r requirements.txt) ],
        },
        gem => {
            file => "Gemfile",
            cmd  => [ $bundler => "install" ],
        },
    };
}

sub list_applications {
    my ( $args, $result ) = @_;

    my $configs = _call_adminbin( 'LIST_APPLICATIONS', [] );

    for my $key ( keys %{$configs} ) {
        next if !keys %{ $configs->{$key} };    # where does this come from?

        my $deps = _get_dep_info_for_app( $configs->{$key} );

        for my $type ( keys %{$deps} ) {
            my $pre = $type eq "gem" && $deps->{$type}{cmd}[0] !~ m/ea-ruby/ ? "BUNDLE_PATH=~/.gem " : "";
            $configs->{$key}{deps}{$type} = -s "$configs->{$key}{path}/$deps->{$type}{file}" ? "cd $configs->{$key}{path} && $pre" . _stringify_cmd( $deps->{$type}{cmd} ) : 0;
        }
    }

    $result->data($configs);

    return 1;
}

sub _stringify_cmd {
    my ($cmd) = @_;
    require String::ShellQuote;
    return String::ShellQuote::shell_quote_best_effort( @{$cmd} );
}

=head2 edit_application()

=head3 Purpose

Modify a Passenger application configured on the cPanel account

=head3 Arguments

See documentation for the C<edit_application()> method in L<Cpanel::Config::userdata::PassengerApps>

=head3 Output

The full configuration for the edited Passenger application

    {
        "deployment_mode" => "production",
        "base_uri"        => "/redmine",
        "path"            => "/home/cptest/redmine",
        "name"            => "redmine",
        "domain"          => "cptest.tld",
        "enabled"         => "1",
        "envvars"         => { "one" => "1" }
    }

=cut

sub edit_application {
    my ( $args, $result ) = @_;

    my $config_hr;
    $config_hr->{'name'} = $args->get_length_required('name');

    # optional parameters
    $config_hr->@{qw(path domain deployment_mode enabled base_uri new_name clear_envvars)} = $args->get(qw(path domain deployment_mode enabled base_uri new_name clear_envvars));
    foreach my $key ( keys %{$config_hr} ) {
        delete $config_hr->{$key} if not defined $config_hr->{$key};
    }
    _populate_envvars( $config_hr, $args );

    my $updated_app_details = _call_adminbin( 'EDIT_APPLICATION', [$config_hr] );
    $result->data($updated_app_details);

    return 1;
}

=head2 unregister_application()

=head3 Purpose

Unregister a Passenger application from the cPanel account

See documentation for the C<unregister_application()> method in L<Cpanel::Config::userdata::PassengerApps>

=head3 Arguments

    name => The name of the application to unregister

=head3 Output

The full configuration for the edited Passenger application

    {
        "deployment_mode" => "production",
        "base_uri"        => "/redmine",
        "path"            => "/home/cptest/redmine",
        "name"            => "redmine",
        "domain"          => "cptest.tld",
        "enabled"         => "1",
        "envvars"         => { "one" => "1" }
    }

=cut

sub unregister_application {
    my ( $args, $result ) = @_;

    my $name = $args->get_length_required('name');

    my $unregister_app_result = _call_adminbin( 'UNREGISTER_APPLICATION', [$name] );
    if ( !$unregister_app_result ) {
        $result->error( 'Failed to unregister application “[_1]”.', $name );
    }

    return $unregister_app_result;
}

=head2 disable_application()

=head3 Purpose

Disable a Passenger application on the cPanel account.

B<Note>: This preserves the application's configuration on the account,
but removes the Apache configuration for the application.

See documentation for the C<disable_application()> method in L<Cpanel::Config::userdata::PassengerApps>

=head3 Arguments

    name => The name of the application to disable

=head3 Output

A boolean value indicating the success of the operation (1 for success).

=cut

sub disable_application {
    my ( $args, $result ) = @_;

    my $name = $args->get_length_required('name');

    my $disable_result = _call_adminbin( 'DISABLE_APPLICATION', [$name] );
    if ( !$disable_result ) {
        $result->error( 'Failed to disable application “[_1]”.', $name );
    }

    return $disable_result;
}

=head2 enable_application()

=head3 Purpose

Enable a Passenger application on the cPanel account.

See documentation for the C<enable_application()> method in L<Cpanel::Config::userdata::PassengerApps>

=head3 Arguments

    name => The name of the application to enable

=head3 Output

A boolean value indicating the success of the operation (1 for success).

=cut

sub enable_application {
    my ( $args, $result ) = @_;

    my $name = $args->get_length_required('name');

    my $enable_result = _call_adminbin( 'ENABLE_APPLICATION', [$name] );
    if ( !$enable_result ) {
        $result->error( 'Failed to enable application “[_1]”.', $name );
    }

    return $enable_result;
}

=head2 ensure_deps()

=head3 Purpose

Ensure configured dependencies for a Passenger application are installed.

=head3 Arguments

First, an C<$args> object w/ the following params:

=over 4

=item app_path

The path of the application relative to C<~>.

=item type

A type of application. Currently it understands the following:

=over 4

=item C<npm>

=back

=back

Second, a C<$result> object.

=head3 Output

The url for using SSE to tail the log of the ensure deps task we just kicked off.

=cut

sub ensure_deps {
    my ( $args, $result ) = @_;

    my ( $type, $app_path ) = $args->get_length_required(qw(type app_path));

    if ( !exists $dep_types{$type} ) {
        $result->error("Unknown application dependency type");
        return;
    }

    # .. alone may not mean path traversal but it is ambiguous so don’t allow it
    my $homedir = Cpanel::PwCache::gethomedir();
    if ( $app_path =~ m/(?:\.\.|\0)/ || !-d "$homedir/$app_path" ) {
        $result->error("Invalid path");
        return;
    }

    my $app     = {};
    my $configs = _call_adminbin( LIST_APPLICATIONS => [] );
    for my $key ( keys %{$configs} ) {
        next if !keys %{ $configs->{$key} };    # where does this come from?

        if ( $configs->{$key}{path} eq "$homedir/$app_path" ) {
            $app = $configs->{$key};
            last;
        }
    }
    my $deps = _get_dep_info_for_app($app);

    require Cpanel::UserTasks;
    my $ut = Cpanel::UserTasks->new();

    local $ENV{HOME}        = $homedir;                                                  # just in case gem/pip/npm rely on HOME being correct
    local $ENV{BUNDLE_PATH} = "$ENV{HOME}/.gem" if $deps->{gem}{cmd}[0] !~ m/ea-ruby/;

    my $task_id = $ut->add(
        subsystem => 'PassengerApps',
        action    => 'ensure_deps',
        args      => {
            app_path => $app_path,
            cmd_json => scalar( Cpanel::JSON::Dump( $deps->{$type}{cmd} ) ),
            log_file => time() . '-ensure_deps.log',
        },
    );
    my $task = $ut->get($task_id);

    if ( !$task ) {
        $result->error("Could not add task");
        return;
    }

    $result->data( { sse_url => $task->{sse_url}, task_id => $task_id } );
    return 1;
}

sub _populate_envvars {
    my ( $config_hr, $args ) = @_;

    my @envvars_names  = $args->get_multiple('envvar_name');
    my @envvars_values = $args->get_multiple('envvar_value');

    # TODO: Better error message
    die Cpanel::Exception::create( 'InvalidParameter', 'You did not specify an equal number of environment variable names and values.' )
      if scalar @envvars_names != scalar @envvars_values;

    $config_hr->{'envvars'}->@{@envvars_names} = @envvars_values;

    return 1;
}

sub _call_adminbin {
    my ( $function, $args ) = @_;
    return Cpanel::AdminBin::Call::call( 'Cpanel', 'passengerapps', $function, @{$args} );
}

1;
