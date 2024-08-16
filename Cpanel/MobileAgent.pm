package Cpanel::MobileAgent;

# cpanel - Cpanel/MobileAgent.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::MobileAgent - Mobile device detection

=head1 SYNOPSIS

  use Cpanel::MobileAgent;
  Cpanel::MobileAgent::is_mobile_or_tablet_agent( $user_agent_string );

=head1 DESCRIPTION

Attempt to detect mobile devices

=head1 SUBROUTINES

=head2 is_mobile_agent( $user_agent_string )

Attempt to detect a mobile device by hardware or mobile device keywords.
B<NOTE>: Does B<not> count an iPad as a mobile device.

=over 3

=item C<$user_agent_string> [in, required]

The user agent string

=back

B<Returns>: True if we detect it is a mobile device, false otherwise.

=cut

sub is_mobile_agent {
    return if !defined $_[0];
    return $_[0] =~
      /HTC_|Android|AU-MIC|AUDIOVOX-|Alcatel-|AnexTek|AvantGo|BlackBerry|Blazer|CDM-|Dopod-|Ericsson|HPiPAQ-|HTC-|Hitachi-|KDDI|LG|MM-|MO01|MOT-|MobilePhone|Motorola|N515i|N525i|NEC-|NOKIA|Nokia|OPWV|Opera mini|PG-|PLS|PM-|PN-|Palm|Panasonic|Pantec|QCI-|RL-|SAGEM|SAMSUNG|SCH|SCP-|SEC-|SGH-|SHARP-|SIE-|SPH|SPV|Samsung|Sendo|Smartphone|SonyEricsson|UP.Browser|UP.Link|V60t|VI600|VK530|VM4050|Vodafone|Windows CE|amoi|hiptop|portalmmm|mobile|Mobile|phone|iPhone/
      && $_[0] !~ /iPad/ ? 1 : 0;
}

=head2 is_mobile_or_tablet_agent( $user_agent_string )

Attempt to detect a mobile device by hardware or mobile device keywords.
B<NOTE>: Does count an iPad as a mobile device.

=over 3

=item C<$user_agent_string> [in, required]

The user agent string

=back

B<Returns>: True if we detect it is a mobile device, false otherwise.

=cut

sub is_mobile_or_tablet_agent {
    return if !defined $_[0];
    return $_[0] =~ /iPad/ || is_mobile_agent( $_[0] );
}

1;
