package Cpanel::Server::SSE::cpanel::UserTasks::Event::Processing;

# cpanel - Cpanel/Server/SSE/cpanel/UserTasks/Event/Processing.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::Server::SSE::cpanel::UserTasks::Event::Processing - SSE event for failure

=head1 SYNOPSIS

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::Processing->new( "This is a Processing" );

=cut

use cPstrict;

use parent 'Cpanel::Server::SSE::cpanel::UserTasks::Event';

use constant EVENT_TYPE => q[task_processing];

1;
