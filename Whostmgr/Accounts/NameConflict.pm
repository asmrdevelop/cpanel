package Whostmgr::Accounts::NameConflict;

# cpanel - Whostmgr/Accounts/NameConflict.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DB::Prefix         ();
use Cpanel::DB::Utils          ();
use Cpanel::Exception          ();
use Cpanel::Validate::Username ();
use Cpanel::Config::DBOwners   ();

#$renamed_from is optional and specifies a username that, if it is the only
#conflicting username, will not trigger an exception. This serves the
#use case of renaming an account rather than creating a new one.
#
sub verify_new_name {
    my ( $new_name, $renamed_from ) = @_;

    _validate_name_for_creation($new_name);

    _check_for_conflicts( $new_name, $renamed_from );

    return 1;
}

#The same as verify_new_name(), except it allows _ and .
#and doesn't accept a $renamed_from parameter.
sub verify_new_name_for_restore {
    my ($new_name) = @_;

    _validate_name_for_restore($new_name);

    _check_for_conflicts($new_name);

    return 1;
}

sub _check_for_conflicts {
    my ( $new_name, $renamed_from ) = @_;

    if ( Cpanel::Validate::Username::reserved_username_check($new_name) ) {
        die Cpanel::Exception::create( 'Reserved', '“[_1]” is a reserved username on this system.', [$new_name] );
    }

    if ( Cpanel::Validate::Username::user_exists($new_name) ) {
        die Cpanel::Exception::create( 'NameConflict', 'This system already has an account named “[_1]”.', [$new_name] );
    }
    if ( Cpanel::Validate::Username::group_exists($new_name) ) {
        die Cpanel::Exception::create( 'NameConflict', 'This system already has a group named “[_1]”.', [$new_name] );
    }

    my $dbowners_ref = Cpanel::Config::DBOwners::load_dbowner_to_user();
    my $new_dbowner  = Cpanel::DB::Utils::username_to_dbowner($new_name);
    if (
           $dbowners_ref->{$new_dbowner}
        && $dbowners_ref->{$new_dbowner} ne $renamed_from    # If the dbowner is the same because its the first 8 characters
                                                             # there is no conflict
    ) {
        die Cpanel::Exception::create( 'NameConflict', 'This system already has a database owner named “[_1]”.', [$new_dbowner] );
    }

    #If the username is as long as the longest possible DB prefix, then we must
    #verify that no other username has the same prefix.
    if ( length($new_name) >= Cpanel::DB::Prefix::get_prefix_length() ) {
        my $db_prefix = Cpanel::DB::Prefix::username_to_prefix($new_name);
        if ( my @dbowner_conflicts = grep { rindex( $_, $db_prefix, 0 ) == 0 } keys %{$dbowners_ref} ) {

            $renamed_from ||= q<>;
            my $old_dbowner = Cpanel::DB::Utils::username_to_dbowner($renamed_from);

            if ( grep { $_ ne $old_dbowner } @dbowner_conflicts ) {
                die Cpanel::Exception::create( 'NameConflict', 'The name of another account on this server has the same initial [quant,_1,character,characters] as the given username ([_2]). Each username’s first [quant,_1,character,characters] must be unique.', [ length($db_prefix), $new_name ] );
            }
        }
    }
}

sub _validate_name_for_creation {
    my ($new_name) = @_;

    # On creation, we don't want to allow '.' and '_' in user names.
    if ( 0 <= index( $new_name, "." ) || !Cpanel::Validate::Username::is_strictly_valid($new_name) ) {
        _die_because_invalid($new_name);
    }

    return 1;
}

sub _validate_name_for_restore {
    my ($new_name) = @_;

    # On transfer, we allow '.' and '_' in user names.
    if ( !Cpanel::Validate::Username::is_valid($new_name) ) {
        _die_because_invalid($new_name);
    }

    return 1;
}

sub _die_because_invalid {
    my ($new_name) = @_;
    die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid username on this system.', [$new_name] );
}

1;
