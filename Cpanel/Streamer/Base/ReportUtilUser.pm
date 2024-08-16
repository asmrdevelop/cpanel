package Cpanel::Streamer::Base::ReportUtilUser;

# cpanel - Cpanel/Streamer/Base/ReportUtilUser.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::Base::ReportUtilUser

=head1 SYNOPSIS

    my $err_id = $streamer->get_error_id();

=head1 DESCRIPTION

This provides methods for streamer modules that use
L<Cpanel::Streamer::ReportUtil> internally.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Streamer';

use Cpanel::Streamer::ReportUtil ();

#----------------------------------------------------------------------

=head1 METHODS

Besides the methods that this class inherits from its base class:

=head2 $id = I<OBJ>->get_error_id()

In the event of failure, the subprocess will try to send an
error ID (cf. L<Cpanel::Exception>) to the parent process, which you can read
via this method.

=cut

*get_error_id = *Cpanel::Streamer::ReportUtil::get_child_error_id;

1;
