# cpanel - Cpanel/FeatureFlags.pm                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FeatureFlags;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures);

use cpcore;

our $VERSION = '1.0.0';

use Cpanel::Exception               ();
use Cpanel::FeatureFlags::Constants ();

use constant MTIME => 9;

=head1 MODULE

C<Cpanel::FeatureFlags>

=head1 DESCRIPTION

C<Cpanel::FeatureFlags> provides tools to check if a product feature is turned on or off. There are
additional helper methods for enabling product features as they become available, and removing them
as they are removed from the product.

All new product features should us these feature flags.

There is a desire to have most new product features disabled by default.  When the product feature
is suitably vetted, it can be enabled. This allows developers to merge changes behind feature flags into the
product while under developement.

A feature flag system is a lot more than just turning on and off individual features. It can be used
to:

=over

=item 1. Enable one of a set of competing features

=item 2. Temporarly disable a buggy feature that made it to production code.

=item 3. Disable deprecated features, but allow customers to reactivate them due to a dependency that has not yet been resolved.

=back

=head2 Special consideration for new applications in development.

To facilitate development we need to have a way to enable features during team development in a consistent way
for the team doing development.

Teams should add their feature flags to the C<add.cfg> when they start using a feature flag. In this way they can share
the same configuration on all the development branches and builds the team uses.

These development flags can be removed from C<add.cfg> before merging to upstream if the feature is not complete by the time
the release is ready for public consumption

=head2 Notes on refactoring existing apps to support feature flags.

When we add feature flags to apps that existed prior to the Feature Flag system, we need to take
care that we don't disable them by default thru this system since customer are expecting them to
continue to be available to parts of the product already.

Be sure to add the new flags for these refactored features to the C<add.cfg> so they will continue
to run on new versions.

=head2 DEFINITIONS

=over

=item gate

a control mechnimis that must be evalutate before a product feature can be used.

=item product feature

an abstract concept encompasing a uniqe set of functionatliy being added to the product.

=item feature flag

an generalized gate controlled by cPanel L.L.C. used to determin if a feature is available in a
given version of the product.

=item cPanel feature

a feature contol mechnism unique to the cPanel UI user access control system. While feature flags
may be used to gate a product feature in the cPanel UI at the release level, they are distict from
cPanel features which are part of the cPanel User Access Control gate.

=back

=head2 GATE CONTROL STACK

Access to features work in a layered stack as shown below. Each gate level must allow
the product feature to run to proceed to the next gate level check.  Only if all the gates
allow the application to run, can the product feature be accessed.

Not all product features use all the gates.

=over

=item Feature Flag (by release)

=item License Flag (by server ip)

=item App Config (by server) - at optional module install time.

=item Application Enablement (by administrator) - varies by product feature.

=item User Access Contol (by user) - systems vary by UI context (WHM, cPanel and Webmail)

=back

=head1 SYNOPSIS

=head2 During an install of the product.

  use Cpanel::FeatureFlags ();
  Cpanel::FeatureFlags::install();

=head2 During an update of the product.

  use Cpanel::FeatureFlags ();
  Cpanel::FeatureFlags::update();

=head2 Use by application developers.

  use Cpanel::FeatureFlags ();

  # Feature Flag guard for linked_nodes application.
  my $feature_enabled = Cpanel::FeatureFlags::is_feature_enabled('linked_nodes');
  if ($feature_enabled) {
    # Do something for linked_nodes application.
    # This usually involes new code.
  }

=head2 Use by resource builders that need to determine what features have been enabled/disabled since last time run.

  my $resource_ts = stat($resource_path);
  my $flags_update_ts = Cpanel::FeatureFlags::last_modified();
  if ($resource_ts < $flags_update_ts) {
    rebuild($resource_path);
  }

=head1 FUNCTIONS

=head2 is_feature_enabled($FEATURE)

Determine if a feature is enabled for the server.

=head3 ARGUMENTS

=over

=item  $FEATURE - C<String>

Unique key identifying the feature.

=back

=head3 RETURNS

C<Boolean>

Boolean representation of existence of the feature flag.

=cut

sub is_feature_enabled ($flag_name) {
    die Cpanel::Exception::create( 'InvalidParameter', 'The argument [list_or_quoted,_1] is required.', ['flag_name'] ) if !$flag_name;
    my $flag_path = _path($flag_name);
    return -e $flag_path ? 1 : 0;
}

=head2 last_modified

Determine when the last change to any feature flag occured on the system.

=head3 RETURNS

C<Number> - The last modify time in seconds since the epoch.

=cut

sub last_modified {
    return ( stat( Cpanel::FeatureFlags::Constants::STORAGE_DIR() ) )[9] || 0;
}

=head2 enable($flag_name)

Enable the application controlled by the flag C<$flag_name>.

=cut

sub enable ($flag_name) {
    return if !_valid_flag($flag_name);
    return _touch( _path($flag_name) );
}

=head2 disable($flag_name)

Disable the application controlled by the flag C<$flag_name>.

=cut

sub disable ($flag_name) {
    return if !_valid_flag($flag_name);
    return _unlink( _path($flag_name) );
}

=head2 install

Install the flags listed in the add.cfg file.

This is used during a new install of the product.

=head3 ARGUMENTS

A hash with the following options:

=over

=item force - boolean

If C<force> has a true value, then the install will run even if the source directory
says its up to date.

=back

=cut

sub install (%args) {
    _ensure_config_dir();
    _ensure_storage_dir();
    _install_flags(%args);
    return 1;
}

=head2 update

Install the flags listed in the add.cfg file and remove the ones in the remove.cfg.

This is used during a product update.

=head3 ARGUMENTS

A hash with the following options:

=over

=item force - boolean

If C<force> has a true value, then the update will run even if the source directory
says its already up to date.

=back

=cut

sub update (%args) {
    _ensure_config_dir();
    _ensure_storage_dir();
    $args{last_modified} = last_modified();
    _install_flags(%args);
    _remove_flags(%args);
    return 1;
}

=head1 PRIVATE METHODS

=head2 _install_flags(%args)

Install the flags listed in the add.cfg file.

=cut

sub _install_flags (%args) {
    my $force         = $args{force};
    my $last_modified = $args{last_modified};

    require Cpanel::FeatureFlags::Config;

    return
      unless $force
      || _has_changes( Cpanel::FeatureFlags::Config::ADD_FLAGS_PATH(), $last_modified );

    my $install_flags = Cpanel::FeatureFlags::Config::get_added_flags();
    foreach my $flag_name ( $install_flags->@* ) {
        next if _ignore_line($flag_name);
        next if !_valid_flag($flag_name);
        _touch( _path($flag_name) );
    }
    return;
}

=head2 _remove_flags(%args)

Remove the flags listed in the remove.cfg file.

=cut

sub _remove_flags (%args) {
    my $force         = $args{force};
    my $last_modified = $args{last_modified};

    require Cpanel::FeatureFlags::Config;

    return
      unless $force
      || _has_changes( Cpanel::FeatureFlags::Config::REMOVE_FLAGS_PATH(), $last_modified );

    my $remove_flags = Cpanel::FeatureFlags::Config::get_removed_flags();
    foreach my $flag_name ( $remove_flags->@* ) {
        next if _ignore_line($flag_name);
        next if !_valid_flag($flag_name);
        _unlink( _path($flag_name) );
    }
    return;
}

=head2 _ignore_line($line)

Ignore whitespace and comment lines.

=head3 ARGUMENTS

=over

=item $line - STRING

=back

=head3 RETURNS

True value when we should ignore the line, false value otherwise

=cut

sub _ignore_line ($line) {

    # skip comment lines
    return 1 if $line =~ m/^[ \t]*#/;

    # skip whitespace only lines
    return 1 if $line =~ m/^[ \t]*$/;

    return;
}

=head2 _path($FLAG)

Calculate the path where a flag is stored on the File System.

=head3 ARGUEMENTS

=over

=item $FLAG - C<String>

The name of the flag.

=back

=head3 RETURNS

C<String> the full path to the location on the File System where the flag file is stored.

=cut

sub _path ($flag_name) {
    return Cpanel::FeatureFlags::Constants::STORAGE_DIR() . q{/} . $flag_name;
}

=head2 _ensure_storage_dir()

Create the storage directory if it does not exist and make sure its permissions are set right.

=cut

sub _ensure_storage_dir() {
    require Cpanel::FeatureFlags::Constants;

    my $dir  = Cpanel::FeatureFlags::Constants::STORAGE_DIR();
    my $perm = Cpanel::FeatureFlags::Constants::STORAGE_DIR_PERMS();

    if ( !-d $dir ) {
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir( $dir, $perm );
    }
    elsif ( ( ( stat(_) )[2] && 07770 ) != $perm ) {
        _chmod( $perm, $dir );
    }
    return 1;
}

=head2 sub _ensure_config_dir() {

Create the configuration directories permissions are set right.

=cut

sub _ensure_config_dir() {
    require Cpanel::FeatureFlags::Constants;

    _chmod(
        Cpanel::FeatureFlags::Constants::CONFIG_DIR_PERMS(),
        Cpanel::FeatureFlags::Constants::CONFIG_DIR()
    );

    return;
}

=head2 _chmod($perm, $path)

Update the permissions for a path.

=cut

sub _chmod ( $perm, $path ) {
    require Cpanel::Autodie;
    return Cpanel::Autodie::chmod( $perm, $path );
}

=head2 _touch($path)

Touch the file path passed in C<$path>.

=cut

sub _touch ($path) {
    require Cpanel::FileUtils::Touch;
    return Cpanel::FileUtils::Touch::touch_if_not_exists($path);
}

=head2 _unlink($path)

Delete the path if it exists C<$path>.

=cut

sub _unlink ($path) {
    require Cpanel::Autodie;
    return Cpanel::Autodie::unlink_if_exists($path);
}

=head2 _has_changes($path, $flags_modified)

Check if there are changes to the feature flags on disk.

=cut

sub _has_changes ( $path, $flags_modified = undef ) {
    my $has_flags = -e $path && !-z _;
    return 0 if !$has_flags;

    my $cfg_modified = ( stat(_) )[MTIME];
    $flags_modified //= last_modified();
    return 0 if $flags_modified >= $cfg_modified;
    return 1;
}

=head2 _valid($flag)

Check if there are risky invalid characters:

=over

=item * empty string or undefined

=item *  .. parent directory traversals

=item * / subdirectorires

=back

=head3 ARGUMENTS

=over

=item C<$flag> - string

The flag to test.

=back

=head3 RETURNS

true value when the C<$flag> does not contain any directory traversal or sub-directory characters in its path. false otherwise.

=cut

sub _valid_flag ($flag) {
    return 0 if !$flag;
    return 0 if $flag =~ m/\.\./;    # no traversals
    return 0 if $flag =~ tr[/][];    # no subdirectories
    return 1;
}

1;
