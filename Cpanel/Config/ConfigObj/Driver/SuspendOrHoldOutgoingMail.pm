package Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail;

# cpanel - Cpanel/Config/ConfigObj/Driver/SuspendOrHoldOutgoingMail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail - Feature showcase META for Suspend Outgoing Mail

=head1 DESCRIPTION

Feature Showcase driver for SuspendOrHoldOutgoingMail

=cut

=head1 SYNOPSIS

    use Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail;

    Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::VERSION;

=cut

=head2 VERSION

alias to value of the $Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META::VERSION

=cut

*VERSION = \$Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META::VERSION;

1;
