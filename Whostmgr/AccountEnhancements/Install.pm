package Whostmgr::AccountEnhancements::Install;

# cpanel - Whostmgr/AccountEnhancements/Install.pm           Copyright 2022 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                       http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Autodie   ();
use Cpanel::Exception ();
use Cpanel::Imports;
use Cpanel::ConfigFiles                     ();
use Cpanel::Transaction::File::JSON         ();
use Whostmgr::AccountEnhancements           ();
use Whostmgr::AccountEnhancements::Validate ();

=encoding utf-8

=head1 NAME

Whostmgr::AccountEnhancements::Install.pm

=head1 DESCRIPTION

This module provides functionality to support installing & uninstalling
Account Enhancements allowing developers to define upgrade paths tied to
specific plugins.

=head1 FUNCTIONS

=head2 install($plugin_id, $enhancement)

Installs an Account Enhancement for a plugin.

=head3 ARGUMENTS

=over

=item plugin_id - string

The plugin_id is equivalent to the feature id used in feature lists
and is used to map the enhancement to the plugin feature. For example, B<wp-toolkit>
is the current id for B<WP Toolkit>.

Validation is performed using L<Whostmgr::AccountEnhancements::Validate::validate_id_format>
and undef checks. No validation is performed to check if the plugin exists to allow for running this
during plugin installation where the plugin may not exist yet.

=item enhancement - hash reference

This parameter is expected to contain the enhancement name and id equivalent to an
instance of L<Whostmgr::AccountEnhancements::AccountEnhancement>.

Validation is performed on both the required name and id key => values using
methods from L<Whostmgr::AccountEnhancements::Validate>.

Expected keys:

=over 1

=item id - string

The id to be used for the enhancement, such as B<wp-toolkit-deluxe>.

=item name - string

The name of the enhancement, such as B<WP Toolkit Deluxe>.

=back

=back

=head3 RETURNS

This function returns 1 upon success and dies in all
other cases.

=head3 THROWS

=over 1

=item When the user does not have root privileges

=item When $plugin_id is undefined or otherwise invalid.

=item When $enhancement is not a hash reference or contains an otherwise invalid name or id.

=item When certain file system operations preventing success occur.

=item When adding the extension fails in L<Whostmgr::AccountEnhancements::add> fails.

=back

=cut

sub install ( $plugin_id, $enhancement ) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    die Cpanel::Exception::create( "InvalidParameter", "The [asis,enhancement] parameter must be a hash reference." ) if ref $enhancement ne 'HASH';
    die Cpanel::Exception::create( "MissingParameter", [ name => 'plugin_id' ] )                                      if !defined($plugin_id);

    eval {    #rewording exception
        Whostmgr::AccountEnhancements::Validate::validate_id_format($plugin_id);
    };
    die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” [asis,plugin_id] parameter is not a valid ID.", [$plugin_id] ) if $@;

    Whostmgr::AccountEnhancements::Validate::validate_name( $enhancement->{'name'} );
    Whostmgr::AccountEnhancements::Validate::validate_id_format( $enhancement->{'id'} );

    my $plugins   = get_installed_plugins();
    my %updates   = %$plugins;
    my $operation = sub { Whostmgr::AccountEnhancements::add( $enhancement->{'name'}, $enhancement->{'id'} ) };

    # there is the assumption that users do not run uninstall
    # check if the plugin/enhancement exists, and attempt to update it instead
    eval { Whostmgr::AccountEnhancements::Validate::name_exists( $enhancement->{'name'} ) };
    my $exception = $@;
    if ($exception) {

        if ( !exists $plugins->{ $enhancement->{name} }{plugin_id} || $plugins->{ $enhancement->{name} }{plugin_id} ne $plugin_id ) {
            die $exception;
        }
        $operation = sub { Whostmgr::AccountEnhancements::update( $enhancement->{'name'}, id => $enhancement->{'id'} ) };

    }

    $updates{ $enhancement->{'name'} } = {
        'plugin_id' => $plugin_id,
        'id'        => $enhancement->{'id'},
    };

    #enhancement needs to exist for operation
    _persist(%updates);
    eval { $operation->() };

    if ($@) {    #rollback
        $exception = $@;
        _persist(%$plugins);
        die($exception);
    }

    return 1;
}

=head2 uninstall($plugin_id)

Remove all Account Enhancements mapped to plugin.

After this method completes successfully it is expected that
the plugin is no longer available on the system. All mappings and
Account Enhancements mapped to the plugin will be removed. However
user defined Account Enhancements using the plugin_id and related user assignments are left intact
so that the configurations remain in place should an admin reinstall the
plugin. For instance when they are debugging or upgrading.

=head3 ARGUMENTS

=over

=item plugin_id - string

The plugin_id is equivalent to the feature id used in feature lists
and is used to map the enhancement to the plugin feature. For example, B<wp-toolkit>
is the current id for B<WP Toolkit>. It is expected that this is the same id used
during install.

Validation is performed using L<Whostmgr::AccountEnhancements::Validate::validate_id_format>
and undef checks. No validation is performed to check if the plugin exists on the system, as it
may have been removed. However any mappings and enhancements are removed.

=back

=head3 RETURNS

This function returns a list of any warnings or dies on invalid input.

=head3 THROWS

=over 1

=item When the user does not have root privileges.

=item When $plugin_id is undefined or otherwise invalid.

=back

=cut

sub uninstall ($plugin_id) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    die Cpanel::Exception::create( "MissingParameter", [ name => 'plugin_id' ] ) if !defined($plugin_id);
    eval {    #rewording exception
        Whostmgr::AccountEnhancements::Validate::validate_id_format($plugin_id);
    };
    die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” [asis,plugin_id] parameter is not a valid ID.", [$plugin_id] ) if $@;

    my $plugins = get_installed_plugins();
    my @names;
    foreach my $name ( keys %$plugins ) {
        if ( exists $plugins->{$name}{'plugin_id'} && $plugins->{$name}{'plugin_id'} eq $plugin_id ) {
            push @names, $name;
        }
    }

    delete @$plugins{@names};

    my @warnings;
    foreach my $name (@names) {
        eval {    #rewording exception
            Whostmgr::AccountEnhancements::delete($name);
        };
        push @warnings, "Unable to remove $name from Feature Manager" if $@;
    }
    _persist(%$plugins);

    return @warnings;
}

=head2 get_installed_plugins()

Retrieve mappings of plugins to their Account Enhancements.
This data is stored as JSON in L<Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_INSTALL_FILE>.

=head3 RETURNS

A hash reference of hash references with the mappings of enhancements and plugins.
The hash is keyed by the enhancement name is expected to be unique system wide.

The values are a hash reference that contain the following:

=over 1

=item plugin_id - string

The plugin/feature id of the plugin.

=item id - string

The enhancement id

=back

Example:

    {
      "WP Toolkit Deluxe" => {
        "plugin_id" => "wp-toolkit",
        "id" => "wp-toolkit-deluxe"
      },
      "Quacken Deluxe" => {
        "id" => "quacken-deluxe",
        "plugin_id" => "release-the-quacken"
      }
    }

=head3 THROWS

=over 1

=item When the user does not have permission via ACL.

=item When certain file system operations preventing success occur.

=back

=cut

sub get_installed_plugins () {

    Whostmgr::AccountEnhancements::Validate::validate_access();
    Cpanel::Autodie::mkdir_if_not_exists( $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_DIR,        0700 );
    Cpanel::Autodie::mkdir_if_not_exists( $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_CONFIG_DIR, 0700 );

    my $plugin_transaction = Cpanel::Transaction::File::JSON->new(
        path          => $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_INSTALL_FILE,
        sysopen_flags => $Cpanel::Fcntl::Constants::O_RDONLY | $Cpanel::Fcntl::Constants::O_CREAT
    ) or die Cpanel::Exception::create( "IO::FileReadError", "The system could not read the installed plugins file." );

    my $plugins = $plugin_transaction->get_data();
    $plugin_transaction->close_or_die();
    $plugins = {} if ref $plugins ne 'HASH';

    return $plugins;
}

=head2 _persist(%installed_plugins)

Save changes to plugin mappings.

=head3 ARGUMENTS

=over 1

=item installed_plugins - hash

This value is expected to contain valid mappings
of enhancements to plugins.

Example:

    (
      "WP Toolkit Deluxe" => {
        "plugin_id" => "wp-toolkit",
        "id" => "wp-toolkit-deluxe"
      },
      "Quacken Deluxe" => {
        "id" => "quacken-deluxe",
        "plugin_id" => "release-the-quacken"
      }
    )

Also see L<Whostmgr::AccountEnhancements::Install::get_installed_plugins>.

=back

=head3 RETURNS

Returns 1 on success, dies otherwise.

=head3 THROWS

=over 1

=item When the user does not have root privileges.

=item When certain file system operations preventing success occur.

=back

=cut

sub _persist (%installed_plugins) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    my $plugin_transaction = Cpanel::Transaction::File::JSON->new(
        path        => $Cpanel::ConfigFiles::ACCOUNT_ENHANCEMENTS_INSTALL_FILE,
        permissions => 0644,
    );

    $plugin_transaction->set_data( \%installed_plugins );
    $plugin_transaction->save_and_close_or_die();

    return 1;
}

1;
