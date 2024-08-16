package Cpanel::Data::Result;

# cpanel - Cpanel/Data/Result.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Data::Result

=head1 SYNOPSIS

    my $yay = Cpanel::Data::Result::create_success('a value');

    my $oops = Cpanel::Data::Result::create_failure('an error');

As a convenience, you can also do:

    my $maybe = Cpanel::Data::Result::try( sub { ... } );

To properly consume these objects, do this:

    my $result = sub_that_returns_a_result_object();

    if ( my $error = $result->error() ) {

        # Handle failure case …
    }
    else {
        my $result = $result->get();   # NB: would die() in the failure case

        # Handle success case …
    }

=head1 DESCRIPTION

This class represents the result of an operation that can either
return a value or fail.

=head1 WHEN TO USE THIS CLASS

Exceptions are a widespread and standard way to report failures in Perl,
but there are contexts where they may not be the best tool for the job.

Examples of where this class may be a better fit than exceptions:

=over

=item * The main use case is “batch” operations, where individual parts
of the request can succeed or fail independently of each other.

=item * Another use case is in refactors of legacy code that doesn’t
expect to catch exceptions.

=back

=head1 SEE ALSO

L<Cpanel::Result> is specific to UAPI and, other than that it represents
the reported result of an operation, bears no relationship to this module.

CPAN’s L<Data::Result> isn’t dissimilar from this module but only
represents boolean results.

=cut

#----------------------------------------------------------------------

use constant {
    _SUCCESS_PKG => __PACKAGE__ . '::Success',
    _FAILURE_PKG => __PACKAGE__ . '::Failure',
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = create_success( $VALUE )

Returns a success-designated instance of this class with $VALUE as the value.
C<$obj-E<gt>get()> will thus return $VALUE, while C<$obj-E<gt>error()> will
return undef.

=cut

# We could avoid a scalar copy here by using \$_[0], but Perl’s
# copy-on-write makes that less gainful than would justify the
# resultant awkwardness of the code.
sub create_success ($value) {
    return bless \$value, _SUCCESS_PKG();
}

=head2 $obj = create_failure( $ERROR )

Returns a failure-designated instance of this class with $VALUE as the value.

$ERROR must be a truthy value, or an exception is thrown.

=cut

sub create_failure ($error) {

    # Check ref() to avoid stringifying an “overload.pm”ed object.
    if ( !ref($error) && !$error ) {
        _carp('Falsy failure is nonsensical!');
    }

    return bless \$error, _FAILURE_PKG();
}

=head2 $obj = try( $CODEREF )

Executes $CODEREF in scalar context. If it succeeds (i.e., doesn’t C<die()>),
then $obj is a success that represents $CODEREF’s return; otherwise,
it represents $CODEREF’s failure.

=cut

sub try ($coderef) {
    local ($@);

    my $result;

    eval { $result = $coderef->(); 1 } or do {
        my $error = $@;
        return bless \$error, _FAILURE_PKG();
    };

    return bless \$result, _SUCCESS_PKG();
}

sub _carp ($msg) {
    local ( $@, $! );
    require Carp;
    return Carp::croak($msg);
}

=head1 INSTANCE METHODS

Instances of this class have the following methods:

=head2 C<error()>

Returns undef on success, or the error on failure.

=head2 C<get()>

Returns the value on success; rethrows the error on failure.

=cut

#----------------------------------------------------------------------

package Cpanel::Data::Result::Success;

use parent -norequire => 'Cpanel::Data::Result';

use constant error => undef;

sub get ($self) {
    return $$self;
}

#----------------------------------------------------------------------

package Cpanel::Data::Result::Failure;

use parent -norequire => 'Cpanel::Data::Result';

# A mite hacky, but might as well reuse the sub.
BEGIN {

    # perlpkg needs this:
    no warnings 'once';

    *error = *Cpanel::Data::Result::Success::get;
}

sub get ($self) {
    return Cpanel::Data::Result::_carp( $$self // '' );
}

1;
