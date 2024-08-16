package Cpanel::Template::Plugin::ExpVar;

# cpanel - Cpanel/Template/Plugin/ExpVar.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## case 53388: currently, this plugin is only used in the cpanel.pl binary,
##   where Cpanel::ExpVar is already compiled in; if this plugin is needed
##   elsewhere, ensure Cpanel::ExpVar is likewise compiled in, or adjust
##   build-tools/cpanelsync_ignore and the %blocked logic in
##   00_check_module_ship.t accordingly.

# use strict;   #not for production
## no critic qw(TestingAndDebugging::RequireUseStrict TestingAndDebugging::RequireUseWarnings)

use base 'Template::Plugin';

use Cpanel::ExpVar ();

# I probably could have done more of these, but only && and || are in use
# so I figure why bother with more than that and //.
# This is only here so that I don't have to use eval on the string returned
# from expvar.
my %comparators = (
    '&&' => sub { $_[0] && $_[1] },
    '||' => sub { $_[0] || $_[1] },
    '//' => sub { $_[0] // $_[1] },
);

sub new {
    my ($class) = @_;
    my $plugin = {
        'expand'          => \&Cpanel::ExpVar::expvar,
        'expand_and_eval' => sub {
            my $str      = Cpanel::ExpVar::expvar(@_);
            my @exploded = split( /\s+/, $str );         # Let's hope the customer doesn't do something like $widdly{     'waa'     }
            my $last_result;
            for my $i ( 0 .. $#exploded ) {
                $last_result //= $exploded[$i];
                my $comp  = $exploded[ $i + 1 ];
                my $right = $exploded[ $i + 2 ];
                return $last_result if !$comp || !exists( $comparators{$comp} );
                $i           = $i + 2;                                          # Warp forward to next comparison set.
                $last_result = $comparators{$comp}->( $last_result, $right );
            }
            return $last_result;
        }
    };
    return bless $plugin, $class;
}

1;
