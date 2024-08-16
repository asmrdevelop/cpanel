package Cpanel::SMTP;

# cpanel - Cpanel/SMTP.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SMTP - exception-throwing wrapper around L<Net::SMTP>

=head1 DISCUSSION

Use of this module follows the same patterns as L<Net::SMTP> except
that errors are represented via thrown C<Cpanel::Exception::SMTP>
instances rather than falsey/undef returns.

This is B<NOT> a subclass of L<Net::SMTP>! Reasons:

=over 4

=item 1. To prevent someone from using a L<Net::SMTP> method
as though it threw exceptions (e.g., if they errantly think the method
has been overridden in this class).

=item 2. To prevent someone from printing directly to the socket,
inadvertently undercutting the necessary encoding for the data to be proper
SMTP. (This happened during development.)

=back

The following methods are implemented:

=over 4

=item * C<new()>

=item * C<host()>

=item * C<mail()>

=item * C<recipient()> (If the C<SkipBad> option is given, an exception thrown
if L<Net::SMTP> rejects all given addresses.)

=item * C<data()>

=item * C<datasend()>

=item * C<flush()>

=item * C<dataend()>

=item * C<reset()>

=item * C<auth()>

=item * C<quit()>

=back

If you need more, please implement them!

=cut

use strict;
use warnings;

use Net::SMTP ();

use Cpanel::Exception ();

#overridden in tests
our $_SMTP_CLASS;

BEGIN {
    $_SMTP_CLASS = 'Net::SMTP';
}

sub new {
    my ( $class, @opts ) = @_;

    #So that the instantiation doesn’t clobber global $@, in case this
    #happens in a DESTROY or some other place where $@ is “special”.
    local $@;

    my $smtp = $_SMTP_CLASS->new(@opts) || do {
        my $err = $@;

        die Cpanel::Exception::create( 'SMTP', 'The system failed to connect to an [output,abbr,SMTP,Simple Mail Transfer Protocol] server ([_1]) because of an error: [_2]', [ "@opts", $err ] );
    };

    return bless [$smtp], $class;
}

sub host {
    my ($self) = shift;

    return $self->[0]->host(@_);
}

sub mail {
    my ( $self, @args ) = @_;

    return $self->[0]->mail(@args) || die Cpanel::Exception::create( 'SMTP', 'The system failed to send the message sender’s identity ([_1]) to the [asis,SMTP] server “[_2]” because of an error: [_3]', [ $args[0], $self->[0]->host(), scalar $self->[0]->message() ] );
}

sub recipient {
    my ( $self, @args ) = @_;

    my $opts_hr = ( 'HASH' eq ref $args[-1] ) && pop @args;
    my $skipbad = $opts_hr                    && $opts_hr->{'SkipBad'};

    if ($skipbad) {
        my @ok = $self->[0]->recipient( @args, $opts_hr );
        $self->_failed_recipient( \@args ) if !@ok;

        return @ok;
    }

    return $self->[0]->recipient( @args, $opts_hr || () ) || $self->_failed_recipient( \@args );
}

sub data {
    my ($self) = shift;

    return $self->[0]->data(@_) || do {
        if (@_) {
            die Cpanel::Exception::create( 'SMTP', 'The system failed to send data to the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );
        }

        die Cpanel::Exception::create( 'SMTP', 'The system failed to start the data transmission to the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );
    };
}

sub datasend {
    my ($self) = shift;

    return $self->[0]->datasend(@_) || die Cpanel::Exception::create( 'SMTP', 'The system failed to send data to the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );
}

sub dataend {
    my ($self) = shift;

    return $self->[0]->dataend() || die Cpanel::Exception::create( 'SMTP', 'The system failed to complete its data transmission to the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );
}

sub flush {
    my ($self) = @_;

    return $self->[0]->flush() || die Cpanel::Exception::create( 'SMTP', 'The system failed to flush its I/O buffers with the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );
}

sub reset {
    my ($self) = @_;

    return $self->[0]->reset() || die Cpanel::Exception::create( 'SMTP', 'The system failed to reset the status of the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );
}

sub auth {
    my ( $self, $user, $pass ) = @_;

    my $result = $self->[0]->auth( $user, $pass ) || die Cpanel::Exception::create( 'SMTP', 'The system failed to authenticate with the [asis,SMTP] server “[_1]” because of an error: [_2]', [ $self->[0]->host(), scalar $self->[0]->message() ] );

    $self->[1]{'did_auth'} = $user;

    return $result;
}

sub quit {
    my ($self) = @_;

    return $self->[0]->quit();
}

#----------------------------------------------------------------------

=head1 CUSTOM METHODS

These methods are unique to this class and do not come from L<Net::SMTP>.

=head2 I<OBJ>->auth_username()

Returns the username that was used in a successful C<auth()> on this
object, or undef if there is no such username.

=cut

sub auth_username {
    my ($self) = @_;

    return $self->[1]{'did_auth'};
}

#----------------------------------------------------------------------

sub _failed_recipient {
    my ( $self, $args_ar ) = @_;

    my $msg = $self->[0]->message();

    if ( defined $msg ) {
        die Cpanel::Exception::create( 'SMTP::FailedRecipient', 'The system failed to send the message [numerate,_1,recipient,recipients] [list_and_quoted,_2] to the [asis,SMTP] server “[_3]” because of an error: [_4]', [ 0 + @$args_ar, $args_ar, $self->[0]->host(), $msg ] );
    }

    die Cpanel::Exception::create( 'SMTP::FailedRecipient', 'The system failed to send the message [numerate,_1,recipient,recipients] [list_and_quoted,_2] to the [asis,SMTP] server ([_3]). [numerate,_1,Is the recipient’s address valid?,Are the recipients’ addresses valid?]', [ 0 + @$args_ar, $args_ar, $self->[0]->host() ] );
}

1;
