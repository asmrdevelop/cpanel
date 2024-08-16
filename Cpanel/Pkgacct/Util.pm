package Cpanel::Pkgacct::Util;

# cpanel - Cpanel/Pkgacct/Util.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Event::Timer ();
use Cpanel::Output       ();

my $DOT_INTERVAL = 1;
my $DOT_COUNT    = 10;
my $DOT_MAX      = 80;

sub create_dot_timer {
    my ( $class, $output_obj ) = @_;

    # Empty string here means no source
    my @partial_message = ( $Cpanel::Output::SOURCE_NONE, $Cpanel::Output::PARTIAL_MESSAGE );

    return Cpanel::Event::Timer->new(
        'interval' => $DOT_INTERVAL,
        'context'  => { 'dots' => 0, 'output_obj' => $output_obj },

        'alarm' => sub {
            my ($context) = @_;

            my $output_obj = $context->{'output_obj'};

            $context->{'dots'} += $DOT_COUNT;

            $output_obj->out( '.' x $DOT_COUNT, @partial_message );

            if ( $context->{'dots'} >= $DOT_MAX ) {
                $output_obj->out( "\n", @partial_message );

                $context->{'dots'} = 0;
            }
        },

        'stop' => sub {
            my ($context) = @_;

            if ( $context->{'dots'} ) {
                my $output_obj = $context->{'output_obj'};

                $output_obj->out("\n");

                $context->{'dots'} = 0;
            }
        }
    );
}

1;
