package Cpanel::Output::Formatted::Terminal;

# cpanel - Cpanel/Output/Formatted/Terminal.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

use parent 'Cpanel::Output::Formatted::Plain';

our $product_dir = '/var/cpanel';

my $_tried_to_load_solarize = 0;

sub _try_to_load_solarize {
    unless ( $INC{'Cpanel/Term/ANSIColor/Solarize.pm'} ) {
        local $SIG{'__DIE__'};
        local $SIG{'__WARN__'};
        eval q{require Cpanel::Term::ANSIColor::Solarize};    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
    }
    return ( $_tried_to_load_solarize = 1 );
}

my $_disable_color;

sub _format_text {
    my ( $self, $color, $text ) = @_;

    if ($color) {
        $self->_disable_color() if !defined $_disable_color;
        if ( !$_disable_color ) {
            _try_to_load_solarize() if !$_tried_to_load_solarize;
            if ( $INC{'Cpanel/Term/ANSIColor/Solarize.pm'} && $color ) {
                return Cpanel::Term::ANSIColor::Solarize::colored( [$color], $text );
            }
        }
    }

    return $self->SUPER::_format_text( $color, $text );
}

sub _disable_color {
    return $_disable_color if defined $_disable_color;

    # Make this module usable in tests that forbid filesystem access.
    local $@;
    eval {
        $_disable_color = -e $product_dir . '/disable_cpanel_terminal_colors' ? 1 : 0;
        $_disable_color ||= -e $product_dir . '/disabled/terminal-colors' ? 1 : 0;
    };

    return $_disable_color;
}

sub _clear_cache {
    undef $_disable_color;
    return;
}

1;

__END__
