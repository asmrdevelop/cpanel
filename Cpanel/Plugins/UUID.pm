package Cpanel::Plugins::UUID;

# cpanel - Cpanel/Plugins/UUID.pm                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::PwCache                      ();
use Cpanel::UUID                         ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Validate::Username           ();
use Cpanel::Validate::FilesystemPath     ();

=head1 MODULE

C<Cpanel::Plugins::UUID>

=head1 DESCRIPTION

C<Cpanel::Plugins::UUID> is a class that provides methods for managing a user's UUID used for PLUGINS.

=head1 ATTRIBUTES

=head2 user - string

The user we want to manage the UUID for.

Under normal usage you will not need to pass this as we can pull the current user from $Cpanel::user.

=cut

has 'user' => (
    is  => 'rw',
    isa => sub ($user) {
        require Cpanel::Validate::Username;
        Cpanel::Validate::Username::user_exists_or_die($user);
    },
    default => sub ($self) {
        return $Cpanel::user || die 'Must set the "user" attribute.';
    },
);

=head2 uuid_file - ro - string

The file that contains the user's UUID.

This file lives in the user's .cpanel directory in their home directory. It will create the .cpanel directory if it does not exist.

=cut

has 'uuid_file' => (
    is      => 'ro',
    lazy    => 1,
    isa     => \&Cpanel::Validate::FilesystemPath::validate_or_die,
    default => sub ($self) {
        my $uuid_dir = $self->_ensure_dot_cpanel_dir();
        return "$uuid_dir/plugin_uuid";
    }
);

=head2 uuid - ro - string

The plugin uuid of this user.

If no uuid currently exists, one will be created and saved for the user.

=cut

has 'uuid' => (
    is  => 'rwp',
    isa => sub ($uuid) {
        require Cpanel::Validate::UUID;
        Cpanel::Validate::UUID::validate_uuid_or_die($uuid);
    },
    default => sub ($self) {

        my $uuid_file = $self->uuid_file();

        if ( !-f $uuid_file || -z $uuid_file ) {
            my $uuid = _gen_uuid();
            $self->save($uuid);
        }

        return $self->read();
    }
);

####################################################
#
# The following methods are used to drop privs since we
# are working in the user's home directory.
#
####################################################

has '_check_privs' => (
    is      => 'ro',
    lazy    => 1,
    builder => 1,
);

sub BUILD ( $self, $args ) {
    $self->_check_privs();
    return;
}

sub _build__check_privs ($self) {
    if ( !$> ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new( $self->user );
    }
    return;
}

#################### Done with privs

=head1 METHODS

=head2 reset - string

This method will reset the user's UUID.

It will unlink the user's UUID file, generate a new UUID, and return it.

=cut

sub reset ($self) {
    my $new_uuid = _gen_uuid();
    $self->_set_uuid($new_uuid);
    $self->save($new_uuid);
    return $self->read();
}

=head2 save - boolean

Writes a UUID to the users UUID file.

returns success or failure.

=cut

sub save ( $self, $uuid ) {
    require Cpanel::FileUtils::Write;
    return Cpanel::FileUtils::Write::overwrite( $self->uuid_file(), $uuid, 0600 );
}

=head2 read - string

Opens and reads the user's UUID file.

Returns the UUID as a string.

=cut

sub read ($self) {
    require Cpanel::Slurper;
    return Cpanel::Slurper::read( $self->uuid_file() );
}

sub _ensure_dot_cpanel_dir ($self) {

    my $home           = Cpanel::PwCache::gethomedir( $self->user );
    my $dot_cpanel_dir = "$home/.cpanel";

    unless ( -d $dot_cpanel_dir ) {
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir_or_die( $dot_cpanel_dir, 0700 );
    }

    return $dot_cpanel_dir;
}

sub _gen_uuid () {
    return Cpanel::UUID::random_uuid();
}

1;
