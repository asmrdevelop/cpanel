
# cpanel - Cpanel/DAV/Backend/CPDAVDCollectionBase.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Backend::CPDAVDCollectionBase;

use cPstrict;

use Cpanel::DAV::Metadata ();
use Cpanel::DAV::Result   ();

use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::DAV::Backend::CPDAVDCollectionBase

=head1 DESCRIPTION

Cpanel::DAV::Backend::CPDAVDCollectionBase

A backend class that has shared methods for managing collections, whether they
be addressbooks or calendars. Used by the respective modules as a base so that
logic can be deduplicated.

=cut

sub _collection_type        { die "Defined in subclass -- like VCALENDAR" }
sub _collection_type_pretty { die "Defined in subclass -- like 'Calendar'" }

# Override keys in subclass/append with SUPER if needed
# 'protected' key means "can I delete this via our codepaths"
# (UI or HTTP DAV DELETE call).
sub _valid_meta_keys { return qw{displayname description type protected} }

# Shared private sub for create/update/remove
# Returns HR of ( $coll_obj, $metadata_hr, $error ); by similar key
my $_fetch_coll_and_meta = sub ( $class, $principal, $path ) {

    # load metadata for collection to report back it's name
    my $coll_hr = {
        "obj" => Cpanel::DAV::Metadata->new(
            'homedir' => $principal->{'owner_homedir'},
            'user'    => $principal->{'name'},
        )
    };
    $coll_hr->{'meta'} = $coll_hr->{'obj'}->load();
    if ( !$coll_hr->{'meta'} ) {
        $coll_hr->{'error'} = "The provided principal, $principal->{'name'}, has no associated metadata\n";
        return $coll_hr;
    }

    # Check/format data for the path if it is provided.
    if ($path) {
        my $slash_pos = rindex( '/', $path );
        $coll_hr->{'path'} = $slash_pos != -1 ? substr( $path, $slash_pos + 1 ) : $path;

        # Tolerate no meta being set for type (create path)
        if ( $coll_hr->{'meta'}{ $coll_hr->{'path'} } && $coll_hr->{'meta'}{ $coll_hr->{'path'} }{'type'} ne $class->_collection_type() ) {
            $coll_hr->{'error'} = "The provided path, $coll_hr->{'path'}, is not a " . $class->_collection_type_pretty() . "\n";    # XXX a versus an... :(
        }

        $coll_hr->{'full_path'} = $principal->{'owner_homedir'} . '/.caldav/' . $principal->{'name'} . '/' . $coll_hr->{'path'};
        if ( !-d $coll_hr->{'full_path'} ) {
            $coll_hr->{'error'} = "The full path to the collection, $coll_hr->{'full_path'}, is not valid or does not exist";
        }
    }

    return $coll_hr;
};

# XXX TODO check lt, maybe these array members need to be subs running maketext
my %strings = (
    'create' => [
        'You have successfully created the collection “[_1]” for “[_2]”.',
        'The system could not create the collection “[_1]”: [_2]',
    ],
    'delete' => [
        'You have successfully deleted the collection “[_1]” for “[_2]”.',
        'The system could not delete the collection “[_1]”: [_2]',
    ],
    'update' => [
        'You have successfully edited the collection “[_1]” for “[_2]”.',
        'The system could not edit the collection “[_1]”: [_2]',
    ],
);
my $_result = sub ( $action, $exception, $calname, $principal = '' ) {
    return Cpanel::DAV::Result->new()->conditional(
        $exception ? 0 : 1,
        lh()->maketext( $strings{$action}->[0], $calname, $principal ),
        lh()->maketext( $strings{$action}->[1], $calname, $exception )
    );
};

# Just here as shared guts between create/update
sub _update_metadata ( $class, $mode, $principal, $path, $opts = {} ) {
    my $coll_hr   = $_fetch_coll_and_meta->( $class, $principal, $path );
    my $exception = $coll_hr->{'error'};

    return $_result->( $mode, $exception, $coll_hr->{'path'} ) if $exception;

    foreach my $key2update ( $class->_valid_meta_keys() ) {
        $coll_hr->{'meta'}{$path}{$key2update} = $opts->{$key2update} if $opts->{$key2update};
    }

    # Modify_metadata expects CALDAV request context, save does not.
    # Since we can enter here in non-HTTP request context, don't use modify
    $exception .= "Failed to save collection metadata: $!\n" if !$coll_hr->{'obj'}->save( $coll_hr->{'meta'} );

    return $_result->( $mode, $exception, $coll_hr->{'path'}, $principal->name() );
}

sub _drop_privs_if_needed {
    my ($user) = @_;
    if ( $> == 0 && $user ne 'root' ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new($user);
    }
    return;
}

=head1 SUBROUTINES

=head2 create_collection

Creates a collection for a principal at the specified path.

Arguments

  - principal      - Cpanel::DAV::Principal
  - path           - String - file path name of the collection,
                     i.e. /home/user/.caldav/user@domain.tld/$path/
  - opts           - Hashref, with the possible elements defined by
                     the respective collection type's module.
                     By default these will have a "displayname" and
                     "description".

Returns

This method returns a Cpanel::DAV::Result object indicating whether the
operation succeeded and containing any relevant message about the outcome.

=cut

sub create_collection ( $class, $principal, $path, $opts = {} ) {

    # Drop privs to user, if needed
    my $privs_obj = _drop_privs_if_needed( $principal->{'owner'} );
    _euid_nonzero_or_die();

    my $user = $principal->name();

    # homedir for current user
    my $homedir = $principal->{'owner_homedir'};
    return Cpanel::DAV::Result->new()->failed(
        404,    # possibly could be a constant
        lh()->maketext(
            'The home directory for “[_1]” does not exist.',
            $principal->{'owner'},
        )
    ) if !-d $homedir;

    # check if it already exists, bail out if so
    if ( -d "$homedir/.caldav/$user/$path" ) {
        return Cpanel::DAV::Result->new()->failed(
            409,    # Closest one that made sense. Not sure how clients will react.
            lh()->maketext(
                'The system could not create the [_1] “[_2]” for “[_3]”. It already exists.',
                $class->_collection_type_pretty(),
                $opts->{'displayname'},
                $principal->name(),
            )
        );
    }

    # XXX Should we worry about the umask here on create?
    require Cpanel::Mkdir;
    Cpanel::Mkdir::ensure_directory_existence_and_mode("$homedir/.caldav/$user/$path");

    require Cpanel::DAV::CaldavCarddav;
    if ( Cpanel::DAV::CaldavCarddav::is_over_quota( $principal->{'owner'} ) ) {
        return Cpanel::DAV::Result->new()->failed(
            507,    # This is specific to DAV and makes sense here
            lh()->maketext(
                'This account is over disk quota, [_1] creation will be skipped.',
                $class->_collection_type_pretty(),
            )
        );
    }
    $opts->{'type'} = $class->_collection_type();

    return $class->_update_metadata( 'create', $principal, $path, $opts );
}

=head2 update_collection

Updates the collection's metadata specified by its path for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - String - path - path in the CalDAV system for the collection.
  - String - opts - k/v pairs to update in your metadata

=cut

sub update_collection ( $class, $principal, $path, $opts = {} ) {
    return $_result->( "update", "No principal passed in", $path ) if !$principal;
    return $_result->( "update", "No path passed in",      $path ) if !$path;
    return $_result->( "update", "No opts passed in",      $path ) if !keys(%$opts);

    my $privs_obj = _drop_privs_if_needed( $principal->{'owner'} );
    _euid_nonzero_or_die();

    return $class->_update_metadata( 'update', $principal, $path, $opts );
}

=head2 remove_collection

Deletes the collection.

Arguments

  - $principal      - A Cpanel::DAV::Principal
  - $path - String - path in the CardDAV system for the collection.

Returns

This method returns a Cpanel::DAV::Result object indicating whether the operation succeeded
and containing any relevant message about the outcome.

=cut

sub remove_collection ( $class, $principal, $path ) {
    my $privs_obj = _drop_privs_if_needed( $principal->{'owner'} );
    _euid_nonzero_or_die();

    my $coll_hr   = $_fetch_coll_and_meta->( $class, $principal, $path );
    my $exception = $coll_hr->{'error'};

    return $_result->( "delete", $exception,                                               $coll_hr->{'path'} ) if $exception;
    return $_result->( "delete", "The collection is protected from deletion in metadata.", $coll_hr->{'path'} ) if $coll_hr->{'meta'}{$path}{'protected'};

    # rm -rf the directory $path given based on the $principal
    # HBHB TODO - we should probably have some sanitization/verification functions in a module somewhere to ensure legitness of paths
    my $full_path = $principal->{'owner_homedir'} . '/.caldav/' . $principal->{'name'} . '/' . $path;
    if ( -d $full_path ) {
        require Cpanel::SafeDir::RM;
        Cpanel::SafeDir::RM::safermdir($full_path);
    }
    elsif ( -e _ ) {
        $exception .= "The provided path, $full_path, is not a directory\n";
    }

    # TODO maybe? do this first so that we can back out the change
    # when the dir fails to remove?
    my $name = $coll_hr->{'meta'}{$path}{'displayname'};
    delete $coll_hr->{'meta'}{ $coll_hr->{'path'} };
    $exception .= "Failed to save updated collection metadata file: $!\n" if !$coll_hr->{'obj'}->save( $coll_hr->{'meta'} );

    # Remove any related sharing entries
    require Cpanel::DAV::CaldavCarddav;
    my $obj = Cpanel::DAV::CaldavCarddav->new(
        'auth_user_caldav_root' => $principal->{'owner_homedir'} . '/.caldav/' . $principal->{'name'},
        'acct_homedir'          => $principal->{'owner_homedir'},
        'sys_user'              => $principal->{'owner'},
        'auth_user'             => $principal->{'name'},
        'username'              => $principal->{'name'},
    );
    my $sharing_hr = $obj->load_sharing();

    # Delete collection if the user was sharing it
    delete $sharing_hr->{ $principal->{'name'} }->{ $coll_hr->{'path'} };
    $obj->save_sharing($sharing_hr);

    return Cpanel::DAV::Result->new()->conditional(
        $exception ? 0 : 1,
        lh()->maketext( 'You have successfully deleted the [_1] “[_2]” for “[_3]”.',    $class->_collection_type_pretty(), $name, $principal->name() ),
        lh()->maketext( 'The system could not delete the [_1] “[_2]” for “[_3]”: [_4]', $class->_collection_type_pretty(), $name, $principal->name(), $exception )
    );
}

sub get_collections ( $class, $principal, $type ) {
    require Cpanel::DAV::CaldavCarddav;
    my $user = $principal->{'name'};
    my $obj  = Cpanel::DAV::CaldavCarddav->new(
        'auth_user_caldav_root' => $principal->{'owner_homedir'} . '/.caldav/' . $principal->{'name'},
        'acct_homedir'          => $principal->{'owner_homedir'},
        'sys_user'              => $principal->{'owner'},
        'auth_user'             => $principal->{'name'},
        'username'              => $principal->{'name'},
    );

    # Mongle things in the way the email wants them, as that's the only
    # code path that uses this currently.
    my $colls      = $obj->get_collections_for_user( $principal->{'name'}, $type );
    my %type_paths = (
        'VADDRESSBOOK' => 'addressbooks',
        'VCALENDAR'    => 'calendars',
    );
    return [
        map {
            {
                'name'        => $colls->{$_}{'displayname'},
                'description' => $colls->{$_}{'description'},
                'path'        => "/$type_paths{$type}/$principal->{'name'}/$_",
            },
        } keys(%$colls)
    ];
}

sub _euid_nonzero_or_die {
    die "EUID 0 (root) is an invalid CPDAVD user" if $> == 0;
    return;
}

1;
