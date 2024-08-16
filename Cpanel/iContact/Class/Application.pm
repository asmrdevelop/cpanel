package Cpanel::iContact::Class::Application;

# cpanel - Cpanel/iContact/Class/Application.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This is a BASE CLASS, intended to simplify error reporting from
# such applications as the SSL pending queue, which runs in the background
# and hence can’t rely on normal error reporting mechanisms.
#
# In theory, users should not want to ignore messages of this kind since
# they represent unrecoverable failures that prevent the user’s request
# from going through.
#
# This should not be used for notices that a user would normally expect to
# receive or where there is a desire to display complex information like
# tables; for that, please make a separate class.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::Exception ();

my @LEVELS = qw(
  warn
  error
);

sub new {
    my ( $class, %opts ) = @_;

    if ( defined $opts{'level'} ) {
        if ( !grep { $_ eq $opts{'level'} } @LEVELS ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid notification level for “[_2]”. The only valid [numerate,_3,level is,levels are] [list_and_quoted,_4].', [ $opts{'level'}, __PACKAGE__, scalar(@LEVELS), \@LEVELS ] );
        }
    }

    return $class->SUPER::new(%opts);
}

sub _required_args {
    return (
        'level',
        'message',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        level            => $self->{'_opts'}{'level'},
        message          => $self->{'_opts'}{'message'},
        application_name => $self->_APPLICATION_NAME(),
    );
}

1;
