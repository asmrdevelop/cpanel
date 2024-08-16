package Cpanel::License::State;

# cpanel - Cpanel/License/State.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::License::State - Tracks the state of the license as the customer changes things in manage 2.

=head1 SYNOPSIS

    use Cpanel::License::State ();

    # 0, 1, 2, 4, ...
    my $state = Cpanel::License::State::current_state();

    # defaults to current state.
    my $state_name = Cpanel::License::State::state_to_name();
    # or...
    my $state_name = Cpanel::License::State::state_to_name($state);

    my $bool = Cpanel::License::State::has_changed(); # Did the license state change since we last looked?
    # Then clear it so we don't report it again.
    Cpanel::License::State::clear_changed();

    # Whenever cpsrvd restarts, there might have been a license state change. This is called to check that.
    Cpanel::License::State::update_state();

=head1 DESCRIPTION

Helps the code base keep track of the license as it changes over time.

=head1 METHODS

=cut

use cPstrict;

use Cpanel::License::Flags ();

use constant LICENSE_FILE => '/usr/local/cpanel/cpanel.lisc';

use constant LICENSE_STATE_DIR              => '/var/cpanel/license_state';
use constant LICENSE_CHANGED_FILE_PATH      => '/var/cpanel/license_state/changed';
use constant LICENSE_STATUS_FILE_PATH       => '/var/cpanel/license_state/state';
use constant TRIAL_LICENSE_STATUS_FILE_PATH => '/var/cpanel/license_state/trial';

our $STATES = {
    NO_LICENSE                     => 0,
    ACTIVE_TRIAL_LICENSE           => 1,
    ACTIVE_TRIAL_EXTENSION_LICENSE => 2,
    ACTIVE_PAID_LICENSE            => 4,
    INACTIVE_TRIAL_LICENSE         => 8,
    INACTIVE_PAID_LICENSE          => 16,
    DEVELOPMENT_LICENSE            => 32,
    UNKNOWN                        => 256,
};

=head2 current_state()

Simply reads the stored state of the license state data as it was last updated by update_state().

=head3 RETURNS

a number which is a power of 2.

=cut

# This will always return a numeric value.
my $_current_state;

sub current_state {
    return $_current_state //= int( readlink(LICENSE_STATUS_FILE_PATH) // $STATES->{'UNKNOWN'} );
}

=head2 state_to_name( $state = current_state() )

use this to convert the numberic state value to a string.

=head3 ARGUMENTS

=over

=item state (optional)

if you pass a numeric value, it will use this value. Otherwise it assumes you just want the current state's name value.

=back

=head3 RETURNS

A string corresponding to known state string constants.

=cut

sub state_to_name ( $state = current_state() ) {
    my %state_names = reverse %$STATES;
    return $state_names{$state} // 'UNKNOWN';
}

=head2 is_expired()

Is there a license right now?

=head3 RETURNS

A boolean value specifying if there is a valid license right now.

=cut

sub is_expired {
    return -s LICENSE_FILE ? 0 : 1;
}

=head2 has_changed()

Has current_state changed since something last queried about it?

NOTE: It is the responsibility of the caller to clear this value.

=head3 RETURNS

A boolean value specifying if the state changed.

=cut

sub has_changed {    # Boolean
    return readlink LICENSE_CHANGED_FILE_PATH ? 1 : 0;
}

=head2 clear_changed()

Clear the tracker that current_state has changed. This will make future calls to has_changed be false.

=head3 RETURNS

Nothing of value.

=cut

sub clear_changed {
    return unlink LICENSE_CHANGED_FILE_PATH;
}

=head2 update_state()

Determines if the license state has changed since this call was last made. This allows us to detect trial license
extensions, inactive prod licenses, etc.

=head3 RETURNS

A boolean indicated if any change was detected.

=cut

sub update_state {
    my $prev_state = current_state();
    $_current_state = _calculate_current();

    return if $prev_state == $_current_state;

    _update_data( LICENSE_STATUS_FILE_PATH,  $_current_state );
    _update_data( LICENSE_CHANGED_FILE_PATH, 1 );

    return 1;
}

sub _get_trial_license_last_expired {
    return readlink TRIAL_LICENSE_STATUS_FILE_PATH // '';
}

sub _set_trial_license_last_expired ($trial_exp_date) {
    return _update_data( TRIAL_LICENSE_STATUS_FILE_PATH, $trial_exp_date );
}

sub _calculate_current {
    my $prev_state = current_state();
    my $state      = is_expired() ? $STATES->{'NO_LICENSE'} : $STATES->{'ACTIVE_PAID_LICENSE'};    # 0, 4

    if ( $state == $STATES->{'ACTIVE_PAID_LICENSE'} ) {                                            # License file exists. - 1, 2, 4, 32
        if ( Cpanel::License::Flags::has_flag('trial') ) {

            return $prev_state if $prev_state eq $STATES->{'ACTIVE_TRIAL_EXTENSION_LICENSE'};      # 2 - It's already an extension. no more magic is needed.

            require Cpanel::Server::Type;
            my $trial_exp_date = Cpanel::Server::Type::get_license_expire_gmt_date();
            if ( $prev_state eq $STATES->{'INACTIVE_TRIAL_LICENSE'} ) {                            # 2 - It was a trial, expired, now it's back. This is an extension.
                $state = $STATES->{'ACTIVE_TRIAL_EXTENSION_LICENSE'};
            }
            else {
                $state = $STATES->{'ACTIVE_TRIAL_LICENSE'};                                        # 1

                # The rest of this code is to try to figure out if we stayed trial but switched licenseid.
                my $prev_trial_exp_date = _get_trial_license_last_expired();
                if ( length $prev_trial_exp_date ) {                                               # Did the expire date for the trial license change?
                    if ( $trial_exp_date ne $prev_trial_exp_date ) {                               # We switched licenses.
                        $state = $STATES->{'ACTIVE_TRIAL_EXTENSION_LICENSE'};                      # 2
                    }
                }
            }
            _set_trial_license_last_expired($trial_exp_date);
        }
        elsif ( Cpanel::License::Flags::has_flag('dev') ) {
            unlink TRIAL_LICENSE_STATUS_FILE_PATH;
            $state = $STATES->{'DEVELOPMENT_LICENSE'};    # 32
        }
        else {
            unlink TRIAL_LICENSE_STATUS_FILE_PATH;
        }
    }
    else {    # Not licensed. - 0, 8, 16
              # We've already determined what type of inactive it was.
        return $prev_state if $prev_state & ( $STATES->{'INACTIVE_TRIAL_LICENSE'} | $STATES->{'INACTIVE_PAID_LICENSE'} );

        # Was previous active something we can label?
        $state = $STATES->{'INACTIVE_PAID_LICENSE'}  if $prev_state & ( $STATES->{'ACTIVE_PAID_LICENSE'} | $STATES->{'DEVELOPMENT_LICENSE'} | $STATES->{'INACTIVE_PAID_LICENSE'} );
        $state = $STATES->{'INACTIVE_TRIAL_LICENSE'} if $prev_state & ( $STATES->{'ACTIVE_TRIAL_LICENSE'} | $STATES->{'ACTIVE_TRIAL_EXTENSION_LICENSE'} | $STATES->{'INACTIVE_TRIAL_LICENSE'} );
    }

    # update cache links.

    return $state;
}

sub _update_data ( $path, $data ) {
    state $dircheck++;

    mkdir LICENSE_STATE_DIR, 0700 if $dircheck == 1;

    unlink $path;
    symlink( $data, $path );

    return;
}

sub _clear_internal_caches {
    undef $_current_state;
    return;
}

1;
