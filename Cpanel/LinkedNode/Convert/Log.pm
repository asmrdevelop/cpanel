package Cpanel::LinkedNode::Convert::Log;

# cpanel - Cpanel/LinkedNode/Convert/Log.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::ProcessLog::AbstractUPIDSuccessFail';

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Log

=head1 SYNOPSIS

See L<Cpanel::ProcessLog::AbtractUPIDSuccessFail>.

=head1 DESCRIPTION

This module implements the L<Cpanel::ProcessLog::AbtractUPIDSuccessFail> framework
for changes to account’s linked nodes.

=cut

use constant _DIR => '/var/cpanel/logs/account_node_conversion';

1;
