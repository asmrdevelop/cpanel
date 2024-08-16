package Cpanel::Server::Type::Log;

# cpanel - Cpanel/Server/Type/Log.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Log

=head1 SYNOPSIS

See L<Cpanel::ProcessLog::AbtractUPIDSuccessFail>.

=head1 DESCRIPTION

This module implements the L<Cpanel::ProcessLog::AbtractUPIDSuccessFail> framework for changes
to server profiles.

=cut

use parent 'Cpanel::ProcessLog::AbstractUPIDSuccessFail';

use constant _DIR => '/var/cpanel/logs/activate_profile';

1;
