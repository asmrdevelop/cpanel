package Cpanel::Config::userdata::PassengerApps;

# cpanel - Cpanel/Config/userdata/PassengerApps.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Config::userdata::PassengerApps - Manage a user's Passenger applications

=head1 SYNOPSIS

    use Cpanel::Config::userdata::PassengerApps;

    my $passenger_app_datastore = Cpanel::Config::userdata::PassengerApps->new({ 'user' => 'myuser' });
    $passenger_app_datastore->register_application({ 'name' => 'yo' });
    $passenger_app_datastore->save_changes_to_disk();

=head1 DESCRIPTION

This module encapsulates the logic to create and manage a user's Passenger applications.

=cut

use Cpanel::LoadFile     ();
use Cpanel::Exception    ();
use Cpanel::LoadModule   ();
use Cpanel::FindBin      ();
use Cpanel::Path::Safety ();
use File::Basename       ();

=head1 CLASS METHODS

=head2 new($args_hr)

Object Constructor.

=over 3

=item C<< \%args_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< user => $username >> [in, required]

The username whose Passenger applications will be manipulated via the object.

=item C<< read_only => 1 >> [in, optional]

B<Default>: 0

If true, this makes the some of the operations noop.

=back

=back

B<Returns>: On failure, throws an exception.  On success, returns an object.

=head2 ensure_paths($user_data_application_hr)

Will ensure that C<$user_data_application_hr> has valid values for `ruby`, `nodejs`, and `python`.

If there is no valid value for one of those keys then the key will not exist.

If there are any problems it will output a warning w/ specifics.

Returns void.

=cut

sub new {
    my ( $class, $opts ) = @_;

    my $self = bless {}, $class;
    $self->_initialize($opts);

    return $self;
}

=head1 OBJECT METHODS

=head2 register_application($opts_hr)

Create a new application with the name specified in C<$opts_hr>. This is a noop when
invoked on a 'read_only' object.

Upon creating the application successfully, the caller must use the C<save_changes_to_disk()> method
in order to save the new application to the disk.

=over 3

=item C<< \%opts_hr >> [in, required]

A hashref with the following keys:

=over 3

=item C<< name => $application_name >> [in, required]

The name to associate with the application.

This name must be B<unique> - if an application by the same name exists, then an
exception is thrown.

=back

=over 3

=item C<< path => $application_path >> [in, required]

The path where the application is located.

=back

=over 3

=item C<< domain => $application_domain >> [in, required]

The domain where the application will be accessed.

=back

=over 3

=item C<< deployment_mode => 'production' >> [in, optional]

Sets the C<PassengerAppEnv> directive for the application.

=back

=over 3

=item C<< base_uri => '/' >> [in, optional]

Sets the C<PassengerBaseURI> directive for the application.

=back

=over 3

=item C<< enabled => 1 >> [in, optional]

Controls whether the application is enabled after it is created.

=back

=over 3

=item C<< envvar => $hashref >> [in, optional]

The environment variables to configure for the application. The hashref
should have the following structure:

    {
        'ENV_VAR_NAME_1' => 'ENV_VAR_VALUE_1',
        'ENV_VAR_NAME_2' => 'ENV_VAR_VALUE_2',
    }

=back

=back

B<Returns>: On failure, throws an exception. On success, the following data is returned in a hashref:

=over 3

=item C<name>

The name of the application.

=item C<path>

The path of the application.

=item C<domain>

The domain where the application will be hosted.

=item C<base_uri>

The base URI of the application.

=item C<enabled>

The status of the application.

=item C<envvars>

A hashref of environment variables for the application.

=back

=cut

sub register_application {
    my ( $self, $opts_hr ) = @_;
    return {}     if $self->{'_read_only'};
    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $valid_opts = $self->_validate_opts_or_die($opts_hr);

    my $data = $self->_read_data();
    die Cpanel::Exception::create( 'EntryAlreadyExists', 'An application with the name “[_1]” already exists.', [ $valid_opts->{'name'} ] )
      if exists $data->{ $valid_opts->{'name'} };

    $data->{ $valid_opts->{'name'} } = $valid_opts;
    $self->ensure_paths( $data->{ $valid_opts->{name} }, 1 );

    $self->{'_transaction_obj'}->set_data($data);

    return $valid_opts;
}

=head2 list_applications()

Lists all of the application configurations for the current user.

B<Returns>: A HashRef of hashes of the form:

    {
        'app name' => {
            'name' => 'app name',
            'path' => 'path of app',
            'domain' => 'domain of app',
            'base_uri' => 'base uri of app',
            'enabled' => 1,
            'envvars' => {},
        },
        'other app' => {
            'name' => 'other app',
            'path' => 'path of app',
            'domain' => 'domain of app',
            'base_uri' => 'base uri of app',
            'enabled' => 1,
            'envvars' => {},
        },
    }

=cut

sub list_applications {
    my ($self) = @_;

    my $data = $self->_read_data();

    return $data || {};
}

=head2 edit_application($opts_hr)

Edit an exisiting application configuration as specified in C<$opts_hr>. This is a noop when
invoked on a 'read_only' object.

Upon editing the application successfully, the caller must use the C<save_changes_to_disk()> method
in order to save the new application to the disk.

B<NOTE>: This method requires the "full set" of C<envvars>, and will replace the set of environment
variables with what is specified.

=over 3

=item C<< \%opts_hr >> [in, required]

A hashref similar to what C<register_application()> takes as input. However only the C<name> is
required, and all of the other parameters are optional.

In addition to those params, this method takes the following:

=over 3

=item C<< new_name => $application_name >> [in, optional]

The new name to associate with the application.

This name must be B<unique> - if an application by the same name exists, then an
exception is thrown.

=back

=over 3

=item C<< clear_envvars => 1 >> [in, optional]

Clear the environment variables configured for the application.

=back

=back

B<Returns>: On failure, throws an exception. On success, returns the updated data with same structure
as C<register_application()> - along with:

=over 3

=item C<previous_app_data>

HashRef containing the details of the app before the edit operation.

=back

=cut

sub edit_application {
    my ( $self, $config_hr ) = @_;

    my $cur_name         = delete $config_hr->{'name'} // die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] );
    my $data             = $self->_read_data();
    my $current_app_data = $data->{$cur_name} // die Cpanel::Exception::create( 'InvalidParameter', 'The application “[_1]” does not exist.', [$cur_name] );

    $self->ensure_paths( $current_app_data, 0 );

    my $new_name = delete $config_hr->{'new_name'};
    die Cpanel::Exception::create( 'EntryAlreadyExists', 'An application with the name “[_1]” already exists.', [$new_name] )
      if ( $new_name && exists $data->{$new_name} );

    my $cur_domain   = $current_app_data->{'domain'};
    my $new_envars   = ( $config_hr->{'envvars'} ? delete $config_hr->{'envvars'} : $current_app_data->{'envvars'} );
    my $new_app_data = {
        %{$current_app_data},
        %{$config_hr},
        ( $new_name ? ( 'name' => $new_name ) : () ),
        'envvars' => ( delete $config_hr->{'clear_envvars'} ? {} : $new_envars ),
    };

    my $new_valid_opts = $self->_validate_opts_or_die($new_app_data);

    delete $data->{$cur_name};
    $data->{ $new_valid_opts->{'name'} } = $new_valid_opts;
    $self->{'_transaction_obj'}->set_data($data);

    return {
        %{$new_valid_opts},
        'previous_app_data' => $current_app_data,
    };
}

=head2 unregister_application($name)

Deletes an application configuration for the name given. This is a noop
when invoked on a 'read_only' object.

Upon deleting the application successfully, the caller must use the C<save_changes_to_disk()> method
in order to save the changes made to the application configurations.

=over 3

=item C<< $name >> [in, required]

The name of the application to delete.

=back

B<Returns>: The hash of the deleted application configurstion on success and C<0> on failure.

=cut

sub unregister_application {
    my ( $self, $name ) = @_;
    return 0 if $self->{'_read_only'};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] ) if !defined $name;

    my $data = $self->_read_data();
    if ( my $info = delete $data->{$name} ) {
        $self->{'_transaction_obj'}->set_data($data);
        return $info;
    }

    return 0;
}

=head2 disable_application($name)

Disables an application. This is a noop when invoked on a 'read_only' object.

Upon disabling an application, the caller must use the C<save_changes_to_disk()> method
in order to save the changes made to the application configuration.

=over 3

=item C<< $name >> [in, required]

The name of the application to disable.

=back

B<Returns>: The hash of the application configuration on success and C<{}> on failure.

=cut

sub disable_application {
    my ( $self, $name ) = @_;
    return 0 if $self->{'_read_only'};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] ) if !defined $name;

    my $data = $self->_read_data();
    die Cpanel::Exception::create( 'InvalidParameter', 'The application “[_1]” does not exist.', [$name] )
      if not exists $data->{$name};

    $data->{$name}->{'enabled'} = 0;
    $self->{'_transaction_obj'}->set_data($data);
    return $data->{$name};
}

=head2 enable_application($name)

Enables an application. This is a noop when invoked on a 'read_only' object.

Upon enabling an application, the caller must use the C<save_changes_to_disk()> method
in order to save the changes made to the application configuration.

=over 3

=item C<< $name >> [in, required]

The name of the application to toggle.

=back

B<Returns>: The hash of the application configuration on success and C<{}> on failure.

=cut

sub enable_application {
    my ( $self, $name ) = @_;
    return 0 if $self->{'_read_only'};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] ) if !defined $name;

    my $data = $self->_read_data();
    die Cpanel::Exception::create( 'InvalidParameter', 'The application “[_1]” does not exist.', [$name] )
      if not exists $data->{$name};

    $data->{$name}->{'enabled'} = 1;
    $self->ensure_paths( $data->{$name}, 0 );

    $self->{'_transaction_obj'}->set_data($data);
    return $data->{$name};
}

=head2 save_changes_to_disk()

Saves any changes to the disk.

B<Returns>: On failure, throws an exception. On success, returns C<1>.

=cut

sub save_changes_to_disk {
    my $self = shift;
    return if $self->{'_read_only'};

    return $self->{'_transaction_obj'}->save_or_die();
}

=head2 change_domain($old_domain, $new_domain)

Changes domains across all configured applications. This is a noop when invoked on a 'read_only' object.

The caller must use the C<save_changes_to_disk()> method
in order to save the changes made to the application configuration.

=over 3

=item C<< $old_domain >> [in, required]

The old domain name to replace.

=item C<< $new_domain >> [in, required]

The new domain name to use.

=back

B<Returns>: C<1> on success and C<0> on failure.

=cut

sub change_domain {
    my ( $self, $old_domain, $new_domain ) = @_;
    return 0 if $self->{'_read_only'};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'old_domain' ] ) if !defined $old_domain;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'new_domain' ] ) if !defined $new_domain;

    my $data = $self->_read_data();

    # 1. edit them all
    my @updated_apps;
    for my $app ( keys %{$data} ) {
        push( @updated_apps, $app ) if $data->{$app}{domain} =~ s/(^|\.)\Q$old_domain\E$/$1$new_domain/;
        $self->ensure_paths( $data->{$app}, 0 );
    }

    # 2. write all to disk
    $self->{'_transaction_obj'}->set_data($data);

    # 3. remove all old includes
    foreach my $name (@updated_apps) {
        $self->remove_apache_conf( $name, $old_domain, { 'force' => 1 } );
    }

    return 1;
}

=head2 change_homedir($old_homedir, $new_homedir)

Changes the home directory across all configured applications, which only affects the B<path> attribute.
This is a noop when invoked on a 'read_only' object.

The caller must use the C<save_changes_to_disk()> method
in order to save the changes made to the application configuration.

=over 3

=item C<< $old_homedir >> [in, required]

The old home directory to replace.

=item C<< $new_homedir >> [in, required]

The new hoem directory to use.

=back

B<Returns>: C<1> on success and C<0> on failure.

=cut

sub change_homedir {
    my ( $self, $old_homedir, $new_homedir ) = @_;
    return 0 if $self->{'_read_only'};

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'old_homedir' ] ) if !defined $old_homedir;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'new_homedir' ] ) if !defined $new_homedir;

    my $data = $self->_read_data();

    foreach my $app ( keys %{$data} ) {
        $data->{$app}->{'path'} =~ s/^\Q$old_homedir\E/$new_homedir/;
        $self->ensure_paths( $data->{$app}, 0 );
    }

    $self->{'_transaction_obj'}->set_data($data);

    return 1;
}

=head2 generate_apache_conf($name)

Generates the apache configuration needed for a Passenger application.

=over 3

=item C<< $name >> [in, required]

The name of the application for which to generate an apache config.

=back

B<Returns>: 1.

=cut

sub generate_apache_conf {
    my ( $self, $name ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] ) if !defined $name;

    my $data = $self->_read_data();

    die Cpanel::Exception::create( 'InvalidParameter', 'The application “[_1]” does not exist.', [$name] )
      if not exists $data->{$name};

    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles::Apache::passenger');
    Cpanel::ConfigFiles::Apache::passenger::generate_apache_conf_for_app( $self->{'user'}, $data->{$name} );

    return 1;
}

=head2 remove_apache_conf($name, $domain, $opts_hr)

Removes the apache configuration for a Passenger application.

=over 3

=item C<< $name >> [in, required]

The name of the application for which to remove a apache config.

=item C<< $domain >> [in, required]

The domain of the application.

=item C<< \%opts_hr >> [in, optional]

A hashref that can consist of the following items:

=over 3

=item C<< user => $user >> [in, optional]

The owner or user of the application.

=item C<< force => $force >> [in, optional]

Force removal of both the ssl and std application configs.

=back

=back

B<Returns>: 1.

=cut

sub remove_apache_conf {
    my ( $self, $name, $domain, $opts_hr ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'name' ] )   if !defined $name;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'domain' ] ) if !defined $domain;

    $opts_hr = {} if !( $opts_hr && 'HASH' eq ref $opts_hr );

    my $user = $self->{'user'};
    if ( exists $opts_hr->{'user'} ) {
        $user = $opts_hr->{'user'};
    }

    my $force = 0;
    if ( exists $opts_hr->{'force'} and $opts_hr->{'force'} ) {
        $force = 1;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles::Apache::passenger');
    Cpanel::ConfigFiles::Apache::passenger::remove_apache_conf_for_app( $user, $domain, $name, $force );

    return 1;
}

=head2 rebuild_apache_confs()

Rebuilds all of the apache configurations for each Passenger app that is currently enabled.

=over 3

=item C<< $old_username >> [in, optional]

The previous username which is used to remove old configurations.

=back

B<Returns>: 1.

=cut

sub rebuild_apache_confs {
    my ( $self, $old_username ) = @_;

    my $data = $self->_read_data();
    foreach my $app ( keys %{$data} ) {
        if ( $old_username && $old_username ne $self->{'user'} ) {
            $self->remove_apache_conf( $app, $data->{$app}->{'domain'}, { 'user' => $old_username, 'force' => 1 } );
        }

        $self->remove_apache_conf( $app, $data->{$app}->{'domain'}, { 'force' => 1 } );

        # only generate configs for enabled applications
        if ( $data->{$app}->{'enabled'} ) {
            $self->generate_apache_conf($app);
        }
    }

    return 1;
}

sub _read_data {
    my $self = shift;
    return $self->{'_data'} if $self->{'_data'} && 'HASH' eq ref $self->{'_data'};

    my $data = $self->{'_transaction_obj'}->get_data();
    $self->{'_data'} = ( ref $data eq 'SCALAR' ? ${$data} : $data ) || {};
    return $self->{'_data'};
}

sub _initialize {
    my ( $self, $opts ) = @_;
    $self->{'user'} = delete $opts->{'user'} // die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] );

    my %new_args = (
        'path'        => $self->_data_store(),
        'permissions' => 0644,
        'ownership'   => [ 0, 0 ],
    );

    if ( $opts && $opts->{'read_only'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::JSONReader');
        $self->{'_read_only'}       = 1;
        $self->{'_transaction_obj'} = Cpanel::Transaction::File::JSONReader->new(%new_args);
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::JSON');
        $self->{'_transaction_obj'} = Cpanel::Transaction::File::JSON->new(%new_args);
    }

    return 1;
}

sub ensure_paths {
    my ( $class, $app, $new ) = @_;

    my %pre_multi_binaries = (
        ruby   => "/opt/cpanel/ea-ruby24/root/usr/libexec/passenger-ruby24",
        nodejs => "/opt/cpanel/ea-nodejs10/bin/node",
        python => "/usr/bin/python3",
    );

    for my $type ( keys %pre_multi_binaries ) {
        if ( !exists $app->{$type} ) {    # this and !$new means they have pre-94/pre_multi_binary-only …
            my $pre_multi_binary = $pre_multi_binaries{$type};
            if ( !$new && -x $pre_multi_binary ) {    # … so set them to that explicitly in case passeneger moves on to anewer version
                $app->{$type} = $pre_multi_binary;
            }
            elsif ( my $current_default = Cpanel::LoadFile::load_if_exists("/etc/cpanel/ea4/passenger.$type") ) {
                if ( !$new ) {
                    warn "The “$app->{name}” application’s “$type” value ($pre_multi_binary) is not executable/does not exist.\n";
                    warn "The current default, $current_default, will be in effect for the “$app->{name}” application.\n";
                }
                $app->{$type} = $current_default;
            }
        }
        else {
            if ( !defined $app->{$type} ) {
                warn "The “$app->{name}” application has “$type” but it is not defined, removing …\n";
                delete $app->{$type};
                next;
            }

            warn "The “$app->{name}” application’s “$type” value ($app->{$type}) is not executable/does not exist.\n" if !-x $app->{$type};
        }
    }

    return;
}

sub _validate_opts_or_die {
    my ( $self, $opts_hr ) = @_;

    my $validation_tests = {
        'name'            => { 'required' => 1, 'test'          => \&_validate_name, },
        'domain'          => { 'required' => 1, 'test'          => \&_validate_domain, },
        'path'            => { 'required' => 1, 'test'          => \&_validate_path, },
        'base_uri'        => { 'required' => 0, 'default'       => '/',          'test' => \&_validate_base_uri },
        'deployment_mode' => { 'required' => 0, 'default'       => 'production', 'test' => \&_validate_deployment_mode },
        'enabled'         => { 'required' => 0, 'default'       => 1,            'test' => \&_validate_enabled },
        'envvars'         => { 'required' => 0, 'default'       => {},           'test' => \&_validate_envvars },
        ruby              => { required   => 0, remove_on_undef => 1,            test   => \&_validate_ruby },
        nodejs            => { required   => 0, remove_on_undef => 1,            test   => \&_validate_nodejs },
        python            => { required   => 0, remove_on_undef => 1,            test   => \&_validate_python },
    };

    my ( @err_collection, $valid_config_hr );
    foreach my $key ( keys %{$validation_tests} ) {
        if ( $validation_tests->{$key}->{'required'} && !defined $opts_hr->{$key} ) {
            push @err_collection, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$key] );
            next;
        }

        if ( defined $opts_hr->{$key} && !defined( eval { $opts_hr->{$key} = $validation_tests->{$key}->{'test'}->( $opts_hr->{$key}, $self->{'user'} ); } ) ) {
            push @err_collection, Cpanel::Exception::create(
                'InvalidParameter',
                'Invalid configuration for the parameter “[_1]”: [_2]',
                [ $key, Cpanel::Exception::get_string_no_id($@) ]
            );
        }
        else {
            $valid_config_hr->{$key} = $opts_hr->{$key} // $validation_tests->{$key}->{'default'};
            delete $valid_config_hr->{$key} if !defined $valid_config_hr->{$key} && $validation_tests->{$key}{remove_on_undef};
        }
    }

    die Cpanel::Exception::create( 'Collection', 'The required parameters are invalid or missing.', [], { exceptions => \@err_collection } ) if scalar @err_collection;

    return $valid_config_hr;
}

=head3 _validate_ruby()

Ensures that the given 'ruby' intepretor is valid.

=over 3

=item Ubuntu/Debian

System ruby is used. An example of a valid interpretor would be '/usr/bin/ruby2.7'.

=back

=over 3

=item RHEL/CentOS/AlmaLinux

May either use system ruby or an intepretor provided by an EA package.

An example system path may be '/usr/bin/ruby'.
An example intepretor provided by an EA package is '/opt/cpanel/ea-ruby27/root/usr/bin/ruby'
or '/opt/cpanel/ea-ruby27/root/usr/bin/passenger-ruby27

=back

=over 3

=item NOTE

ruby will always be installed as a dependency of ea-apache24-mod-passenger which is a required
package to reach this code path

=back

=cut

sub _validate_ruby {
    my ( $bin, $user ) = @_;
    $bin = _sanitize_interpreter_path($bin);
    my $bin_name = File::Basename::basename($bin);
    return $bin if defined $bin && -x $bin && $bin_name =~ m{^(?:passenger-)?ruby(?:[0-9.])*$} && ( $bin eq ( Cpanel::FindBin::findbin($bin_name) // '' ) || $bin =~ m{^/opt/cpanel/.+/(?:passenger-)?ruby\d*$} );
    return;
}

=head3 _validate_nodejs()

Ensures that the given 'node' intepretor is valid.

=over 3

=item Ubuntu/Debian

System node is used on Ubuntu.
If node is installed, an example path is '/usr/bin/nodejs'
If node is not installed, then a fake interpretor is used.
The path for this is '/usr/local/bin/ea-passenger-runtime_nodejs-is-not-installed'

=back

=over 3

=item RHEL/CentOS/AlmaLinux

System node can be used.
An example path if system node is in use is '/usr/bin/node'.
Node can also be provided via an EA package.  An example path from an EA
package is '/opt/cpanel/ea-nodejs10/bin/node'

=back

=cut

sub _validate_nodejs {
    my ( $bin, $user ) = @_;
    $bin = _sanitize_interpreter_path($bin);
    my $bin_name = File::Basename::basename($bin);
    return $bin if defined $bin && -x $bin && ( $bin_name eq 'ea-passenger-runtime_nodejs-is-not-installed' || $bin_name =~ m{^node(?:js)?$} ) && ( $bin eq ( Cpanel::FindBin::findbin($bin_name) // '' ) || $bin =~ m{^/opt/cpanel/.+/node$} || $bin eq '/usr/local/bin/ea-passenger-runtime_nodejs-is-not-installed' );
    return;
}

=head3 _validate_python()

Ensures that the given 'python' intepretor is valid.

System python is always used, and should always be installed.
Example paths are '/usr/bin/python', '/usr/bin/python3', and '/usr/bin/python3.8'

=cut

sub _validate_python {
    my ( $bin, $user ) = @_;
    $bin = _sanitize_interpreter_path($bin);
    my $bin_name = File::Basename::basename($bin);
    return $bin if defined $bin && -x $bin && $bin_name =~ m{^python[0-9a-z.]*$} && $bin eq Cpanel::FindBin::findbin($bin_name);
    return;
}

sub _sanitize_interpreter_path {
    my ($path) = @_;
    $path = Cpanel::Path::Safety::make_safe_for_path($path);
    $path =~ s{[\t\n\v]}{}gxms;
    return $path;
}

sub _sanitize_path {
    my ( $unsanatized_path, $user ) = @_;
    require Cpanel::SafeDir::Fixup;
    require Cpanel::PwCache;
    my $homedir = Cpanel::PwCache::gethomedir($user);
    return Cpanel::SafeDir::Fixup::homedirfixup( $unsanatized_path, $homedir, $homedir );
}

# For mocking in tests.
sub _base_dir {
    return '/var/cpanel/userdata';
}

sub _data_store {
    my $self = shift;
    return _base_dir() . '/' . $self->{'user'} . '/applications.json';
}

sub _validate_name {
    my ( $name, $user ) = @_;
    die Cpanel::Exception::create( 'InvalidParameter', 'The name must be 50 characters or less, start with a letter or a number, and may only contain: spaces, numbers, letters, hyphens, and underscores.' )
      if $name !~ m/\A[0-9a-zA-Z][0-9a-zA-Z_\- ]{0,49}\z$/;
    return $name;
}

sub _validate_domain {
    my ( $domain, $user ) = @_;
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    die Cpanel::Exception::create( 'InvalidParameter', 'The domain “[_1]” does not belong to “[_2]”.', [ $domain, $user ] )
      if Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ne $user;
    return $domain;
}

sub _validate_path {
    my ( $path, $user ) = @_;
    $path = _sanitize_path( $path, $user );

    # Disallow the '${' literal in the path, as we can not escape it properly
    die Cpanel::Exception::create( 'InvalidParameter', 'The application path must not contain [asis,Apache] variable substitution literals: [_1]', ['${'] )
      if index( $path, '${' ) != -1;

    # Prevent relative paths from being used.
    # This also does the general validation (such path length, etc) checks.
    Cpanel::LoadModule::load_perl_module('Cpanel::Validate::FilesystemPath');
    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($path);

    Cpanel::LoadModule::load_perl_module('Cpanel::PwCache');
    my $user_homedir = Cpanel::PwCache::gethomedir($user);
    die Cpanel::Exception::create( 'InvalidParameter', 'The application path must be a subdirectory within the user’s home directory.' )
      if $path =~ m/\A(?:\Q$user_homedir\E)?(?:[\/]+)?\z/;

    return $path;
}

sub _validate_base_uri {
    my ( $value, $user ) = @_;

    # References:
    # RFC 2396
    # Data::Validate::URI

    if (
        # Due to discrepencies in how mod_passenger handles the BaseURI directives, we
        # limit users to a stricter set of rules than what is generally allowed in URIs.
        #
        # For us,the base_uri must be:
        # - just a slash or
        # - a string that starts with a slash and
        #    * contains only alphanumeric chars, slashes (/), hyphens, and underscores
        #    * does not end in a slash
        $value ne '/' && ( $value !~ m/\A\/[A-Za-z0-9\/\-_]+?\z/ || substr( $value, -1 ) eq '/' )
    ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,Base URI] must begin with a single slash ([asis,/]) and may not contain spaces, special characters or a trailing slash.', [$value] );
    }
    return $value;
}

sub _validate_deployment_mode {
    my ( $mode, $user ) = @_;
    die Cpanel::Exception::create( 'InvalidParameter', 'The application deployment mode must not exceed 50 characters and may only contain the following characters: [join, ,_1]', [ [ 'a-z', 'A-Z', '0-9', '_', '-' ] ] )
      if $mode !~ m/\A[A-Za-z0-9-_]{1,50}\z/;
    return $mode;
}

sub _validate_enabled {
    my ( $enabled, $user ) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Validate::Boolean');
    Cpanel::Validate::Boolean::validate_or_die($enabled);
    return $enabled;
}

sub _validate_envvars {
    my ( $env_vars, $user ) = @_;

    if ( 'HASH' eq ref $env_vars ) {
        foreach my $env_name ( keys %{$env_vars} ) {
            die Cpanel::Exception::create(
                'InvalidParameter', 'The environment variable name, “[_1]”, is invalid. Environment variable names must not begin with a number, must not be longer than 256 characters, and may only contain the following characters: [join, ,_2]',
                [ $env_name, [ 'a-z', 'A-Z', '0-9', '_', '-' ] ]
            ) if $env_name !~ m/\A[A-Za-z-_][A-Za-z0-9-_]{0,255}\z/;

            die Cpanel::Exception::create(
                'InvalidParameter', 'The environment variable value, “[_1]”, is invalid. Environment variable values must contain fewer than 1024 [asis,ASCII] printable characters.',
                [ $env_vars->{$env_name} ]
            ) if $env_vars->{$env_name} !~ m/\A[[:print:]]{1,1024}\z/a;

            die Cpanel::Exception::create(
                'InvalidParameter', 'The environment variable value, “[_1]”, is invalid. Environment variable values must not contain [asis,Apache] variable substitution literals: [_2]',
                [ $env_vars->{$env_name}, '${' ]
            ) if index( $env_vars->{$env_name}, '${' ) != -1;
        }

        return $env_vars;
    }

    die Cpanel::Exception::create( 'InvalidParameter', q{The “[_1]” data parameter must be a “[_2]” type.}, [ 'envvars', 'hashref' ] );
}

1;
