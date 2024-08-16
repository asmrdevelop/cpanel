package Cpanel::EventHandler;

# cpanel - Cpanel/EventHandler.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel        ();
use Cpanel::Hooks ();
use Cpanel::Debug ();

our $VERSION = 4.0;

our $customEvents = 0;
our $hooks        = 0;
my $customEventHandler = 0;

sub EventHandler_init {
    $Cpanel::NEEDSREMOTEPASS{'EventHandler'} = 1;
    if ( Cpanel::Debug::debug_hooks_value() ) {
        $hooks = 1;
    }
    if ( -e '/usr/local/cpanel/Cpanel/CustomEventHandler.pm' ) {
        eval {
            require Cpanel::CustomEventHandler;
            $customEventHandler = 1;
            $customEvents       = 1;
        };
    }
    if ( Cpanel::Hooks::hooks_exist_for_category('Cpanel') ) {
        $hooks        = 1;
        $customEvents = 1;
    }
    return 1;
}

sub _event {    ## no critic qw(ProhibitManyArgs)
    my ( $apiv, $type, $module, $event, $cfgref, $dataref ) = @_;
    $module //= '';

    my $lc_module = lc $module;

    # Skip locale module loading errors, they are to be expected
    if ( $module && $Cpanel::CPERROR{$lc_module} && $Cpanel::CPERROR{$lc_module} !~ m{Can't locate .*Locales/.*\.pm in \@INC} ) {
        Cpanel::Debug::log_warn("Encountered error in ${module}::${event}: $Cpanel::CPERROR{$lc_module}");
    }

    # if $result = 0, it will prevent the API call from being executed.
    my ( $ran, $result, $msgs ) = ( 0, 1, undef );

    if ( $customEvents && $customEventHandler ) {
        $ran    = 1;
        $result = Cpanel::CustomEventHandler::event( $apiv, $type, $lc_module, $event, _get_cfgref_arg( $apiv, $cfgref ), $dataref );
    }

    if ( $hooks && $result ) {
        $ran = 1;
        ( $result, $msgs ) = Cpanel::Hooks::hook(
            {
                'category'      => 'Cpanel',
                'event'         => "Api$apiv\:\:$module\:\:$event",
                'stage'         => $type,
                'escalateprivs' => 1,
            },
            {
                'args'   => $cfgref,
                'output' => $dataref,
                'user'   => $Cpanel::user,
            },
        );
    }
    return ( $ran, $result, $msgs );
}

# type = pre
# module = Cpanel::<modname>
# event = the event--e.g., addpop
# cfg ref is a hash of the conf variables passed to the event. If its a legacy event, the hash keys are numbered, newer events have names.
# dataref = the data returned from the event (post events only)
*pre_event = \&_event;

# type = post
# module = Cpanel::<modname>
# event = the event--e.g., addpop
# cfg ref is a hash of the conf variables passed to the event. If its a legacy event, the hash keys are numbered, newer events have names.
# dataref = the data returned from the event (post events only)
*post_event = \&_event;

#
# Compat Layer
#
*event = \&_event;

# Generate a configuration hashref
# If it is api1 we pass the array into _cahashref and get back
# a hash ref
sub _get_cfgref_arg {
    my ( $apiv, $cfgref ) = @_;
    return ( $apiv == 1 && ref($cfgref) eq 'ARRAY' ? _cahashref(@$cfgref) : $cfgref );
}

sub pre_api {
    my ( $module, $func, $args, $result ) = @_;

    # Standard Hooks
    my $status = _uapi_std_hook( $module, $func, $args, $result, 'pre' );

    # Custom Event Handlers
    if ($customEventHandler) {
        $status &&= Cpanel::CustomEventHandler::event( 3, 'pre', $module, $func, $args, $result );
    }

    return $status ? 1 : 0;
}

sub post_api {
    my ( $module, $func, $args, $result ) = @_;

    # Standard Hooks
    _uapi_std_hook( $module, $func, $args, $result, 'post' );

    # Custom Event Handlers
    if ($customEventHandler) {
        return Cpanel::CustomEventHandler::event( 3, 'post', $module, $func, $args, $result );
    }

    return 1;
}

sub _uapi_std_hook {
    my ( $module, $func, $args, $result, $stage ) = @_;

    my ( $status, $hooks_msgs ) = Cpanel::Hooks::hook(
        {
            'category'      => 'Cpanel',
            'event'         => "UAPI\:\:$module\:\:$func",
            'stage'         => $stage,
            'escalateprivs' => 1,
        },
        {
            'args'   => $args->{_args},
            'result' => $result->{data},
            'user'   => $Cpanel::user,
        },
    );

    if ( ref $hooks_msgs eq 'ARRAY' ) {
        foreach my $msg ( @{$hooks_msgs} ) {
            if ($status) {
                $result->raw_message($msg);
            }
            else {
                $result->raw_error($msg);
            }
        }
    }

    return $status;
}

sub _cahashref {
    if ( ref $_[0] eq 'HASH' ) {
        return $_[0];
    }

    #coerece an array into a hash reference
    my $i = 0;
    return { map { 'param' . $i++ => $_; } @_ };
}

1;
