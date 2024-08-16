package Cpanel::AdminBin::Script::Call;

# cpanel - Cpanel/AdminBin/Script/Call.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

=head1 NAME

Cpanel::AdminBin::Script::Call

=head1 DESCRIPTION

If you want to write a new adminbin, you can use this module (or one of
the related ones) to accomplish that with minimal boilerplate compared
to traditional adminbins.

This base class for admin modulinos provides a more streamlined interaction
pattern than "Full" or "Simple" and should probably be preferred for all
new development.

=head2 Adminbin mode

In order to write your adminbin using Cpanel::AdminBin::Script::Call, make sure
to set B<mode=full> in youradminbin.conf. B<mode=simple> will not work with
this adminbin class.

=head2 To write a new adminbin with two commands, DO_SOMETHING and DO_SOMETHING_ELSE

  use base 'Cpanel::AdminBin::Script::Call';

  __PACKAGE__->run(alarm => 120); # time out if the adminbin takes more than 2 minutes

  sub DO_SOMETHING {
     my ( $self, @args ) = @_;
     my $user = $self->get_caller_username();
     ...
     return @whatever    #can also be a scalar
  }

  sub DO_SOMETHING_ELSE {
     my ( $self, @args ) = @_;
     my $user = $self->get_caller_username();
     ...
     return @whatever;
  }

  sub _actions {
      return qw(DO_SOMETHING DO_SOMETHING_ELSE);
  }

=head2 To call the adminbin:

  #calls the $FUNC in scalar context
  my $data = Cpanel::AdminBin::Call::call( $namespace, $module, $FUNC, @args );

  #list context
  my @data = Cpanel::AdminBin::Call::call( $namespace, $module, $FUNC, @args );

=cut

use Cpanel::AdminBin::Script::Full ();
use parent                         qw{ -norequire Cpanel::AdminBin::Script::Full };

use Try::Tiny;

*get_arguments = \&Cpanel::AdminBin::Script::Full::get_extended_arguments;

sub _return_admin_payload {    ##no critic qw(RequireArgUnpacking)
    my ( $self, $args_ar ) = ( shift, \@_ );

    my %response = (
        status  => 1,
        payload => $args_ar,
    );

    return $self->SUPER::_return_admin_payload( \%response );
}

sub die {
    my ( $self, $err ) = @_;

    #TODO: Provide a means to serialize a Cpanel::Exception object.
    my %response = (
        status => 0,
        class  => ( ref $err ),
    );

    if ( try { $err->isa('Cpanel::Exception') } ) {
        @response{qw(error_id error_string)} = ( $err->id(), $err->to_locale_string_no_id() );
    }
    else {
        @response{qw(error_id error_string)} = ( undef, $err );
    }

    return $self->SUPER::_return_admin_payload( \%response );
}

*_catch_die = \&die;

sub _dispatch_method {
    my ($self) = @_;

    my ( $metadata_hr, $args_ar ) = @{ $self->get_arguments() };

    my $method = $self->get_action();

    my $todo_cr = $self->can($method) or do {
        CORE::die("Unknown method: $method");
    };

    $self->pre_execute_hook(
        $metadata_hr,
        $args_ar,
    );

    return $metadata_hr->{'wantarray'}
      ? $self->$method(@$args_ar)    #assume list context
      : scalar $self->$method(@$args_ar);
}

sub pre_execute_hook { }

1;
