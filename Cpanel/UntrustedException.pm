
# cpanel - Cpanel/UntrustedException.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UntrustedException;

use strict;
use warnings;

use overload ( '""' => \&stringify, fallback => 1 );

=head1 NAME

Cpanel::UntrustedException - Wrapper class for structured exception info from untrusted sources

=head1 SYNOPSIS

  die Cpanel::UntrustedException->new(
    class    => $exception_class,
    string   => $error_message,
    longmess => $longmess,
    metadata => $metadata,
  );

=head1 WHY

This module is a lightweight wrapper for structured exception data that originated from an untrusted
source. An example of an untrusted source is a cPanel user on a server where root is performing
some operation with reduced privileges on behalf of the user and needs to receive an error report
from the unprivileged process. In the past, when the error in question was a Cpanel::Exception object,
these error reports were limited to stringified versions of those objects. In other words, we
would get the base message followed by the "longmess" (stack trace). This had two major limitations:

=over

=item * If we wanted to hide the non-user-friendly longmess, we were out of luck because all we had
was the pre-concatenated string.

=item * If we wanted to show any additional metadata belonging to the exception object that doesn't
get integrated into the default stringification, we were out of luck because all we had was the
default stringification.

=back

You might be tempted to ask, "Why not just transport the exception guts back to the parent and re-bless
them into the original class?" Well, this comes with a certain level of risk due to the complexity of
Cpanel::Exception. Although possibly not the only problem, one known risk involves the use of make~text()
with potentially-untrusted bracket notation. If the code that generated the exception is responsible for
providing the locale string (with bracket notation), as is sometimes the case, then it would not be safe
for the privileged code on the receiving end to execute this bracket notation to render the message due
to code execution paths in bracket notation itself.

The solution implemented here is a simple wrapper that encapsulates the commonly needed attributes of an
exception object (class name, message, longmess, additional data) with a default stringifier similar to
that of Cpanel::Exception but without the risk associated with using untrusted data for anything other
than returning it as an attribute value.

=head1 PAIRS WELL WITH Cpanel::ForkSync

The class/string/longmess interface of Cpanel::UntrustedException is designed to
work with the class/string/longmess provided by Cpanel::ForkSync. (See SYNOPSIS above.)
Cpanel::ForkSync itself instantiates a Cpanel::UntrustedException object to wrap exception
data coming back from the child.

However, it may be used for any exceptions where the messages are coming from an untrusted
source, and indeed any exceptions where the string is pre-rendered.

=head1 DEFAULT STRINGIFICATION

Like Cpanel::Exception, Cpanel::UntrustedException uses C<overload> to provide automatic
stringification. You may embed a Cpanel::UntrustedException object directly into a string
if all you care about is the default class/string/longmess concatenated output.

=head1 CONSTRUCTION

=head2 Parameters

=over

=item * string - String - (Required) The short-form error message, pre-rendered (not bracket notation).

=item * class - String - (Optional) If the error originated on the untrusted side as an exception object,
this field should contain the full class name. For example: Cpanel::Exception::RemoteSCPError.

=item * longmess - String (Optional) If the error originated fon the untrusted side as an exception object,
this field should contain the "longmess" (stack trace).

=item * metadata - Hash ref (Optional) If you're interested in including the metadata from the original
exception, you may add it here. Each field within this hash ref will then become accessible via C<get()>.

=back

=cut

sub new {
    my ( $package, %params ) = @_;

    my $self = {
        string   => $params{string},
        class    => $params{class},
        longmess => $params{longmess},
        metadata => $params{metadata},
    };

    return bless $self, $package;
}

=head1 ACCESSOR METHODS (read-only)

=head2 class()

Returns the exception class name. Example: Cpanel::Exception::RemoteSCPError

If the exception in question did not originate as a blessed object, then this
will be undefined.

=cut

sub class {
    my ($self) = @_;
    return $self->{class};
}

=head2 string()

Returns the rendered exception string with placeholders already filled out.

This should always be defined wnhether the exception in question originated as a
blessed object or not.

=cut

sub string {
    my ($self) = @_;
    return $self->{string};
}

=head2 longmess()

Returns the "longmess" (stack trace) from the exception.

If the exception in question did not originate as a blessed object, then this
will be undefined.

=cut

sub longmess {
    my ($self) = @_;
    return $self->{longmess};
}

=head2 get(ATTR)

Returns the exception metadata attribute specified by ATTR. If no such attribute exists,
returns undef.

=cut

sub get {
    my ( $self, $attr ) = @_;
    return $self->{metadata}{$attr};
}

# Analogous to Cpanel::Exception::Core::_spew, but using the pre-rendered string from the untrusted source (does not call make~text/make~var)
sub stringify {
    my ($self) = @_;

    if ( $self->{class} ) {
        return $self->{class} . '/' . join "\n", $self->{string} || '<no message>', $self->{longmess} || '';
    }

    return $self->{string};
}

1;
