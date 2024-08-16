package Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure;

# cpanel - Cpanel/Server/SSE/cpanel/UserTasks/Event/Failure.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure - SSE event for failure

=head1 SYNOPSIS

    my $event = Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure->new( "This is a Failure" );

=head1 FUNCTIONS

=head2 view Cpanel::Server::SSE::cpanel::UserTasks::Event

=cut

use cPstrict;

use parent 'Cpanel::Server::SSE::cpanel::UserTasks::Event';

use constant EVENT_TYPE => q[task_failed];

1;
