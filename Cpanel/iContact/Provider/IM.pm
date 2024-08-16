
# cpanel - Cpanel/iContact/Provider/IM.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::iContact::Provider::IM;

use strict;

use Cpanel::Context       ();
use Cpanel::FHUtils::Tiny ();

use parent 'Cpanel::iContact::Provider';

###########################################################################
#
# Method:
#   get_im_subject_and_message
#
# Description:
#    Find a the most suitable subject and body from iContact args
#    for an 'im' (plaintext)  notification
#
# Parameters:
#   none
#
# Exceptions:
#   Will die if there is no plain text notification data
#
# Returns:
#   0 - A plaintext message subject
#   1 - A plaintext message body
#
sub get_im_subject_and_message {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $args_hr = $self->{'args'};

    #
    # Note: we reject text_body if its a file handle because it can only be read once and a
    # im_message should have already been provided in this case.
    #
    if ( !$args_hr->{'im_message'} && ( !exists $args_hr->{'text_body'} || Cpanel::FHUtils::Tiny::is_a( $args_hr->{'text_body'} ) ) ) {
        die "Cannot send instant message because 'im_message' and 'text_body' are not available.";
    }
    return ( $args_hr->{'im_subject'} || $args_hr->{'subject'}, $args_hr->{'im_message'} || ${ $args_hr->{'text_body'} } );
}

1;
