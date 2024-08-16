package Cpanel::SSL::DCV::Ballot169::Constants;

# cpanel - Cpanel/SSL/DCV/Ballot169/Constants.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::Ballot169::Constants - Accommodate new DCV urls from Ballot 169

=head1 SYNOPSIS

    use Cpanel::SSL::DCV::Ballot169::Constants;

    print Cpanel::SSL::DCV::Ballot169::Constants::URI_DCV_RELATIVE_PATH();

=head1 DESCRIPTION

see https://cabforum.org/2016/08/05/ballot-169-revised-validation-requirements/
which specifies the directory for HTTP DCV to be /.well-known/pki-validation/

=cut

use constant {
    URI_DCV_RELATIVE_PATH => '.well-known/pki-validation',

    # The (?: Ballot169) is used to keep track of this rule
    # so we know what is belongs to (like we do with Comodo DCV)
    REQUEST_URI_DCV_PATH => '^/\\.well-known/pki-validation/(?: Ballot169)?',

};

1;
