package Cpanel::Email::Send;

# cpanel - Cpanel/Email/Send.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Email::Send - Generate a Cpanel::Email::Object email and send it

=head1 SYNOPSIS

    use Cpanel::Email::Send;

    Cpanel::Email::Send::email_message(
        {
            # Cpanel::Email::Object params
        },
        {
            # Transport configuration
        }
    )

=head1 DESCRIPTION

Generate a email by passing arguments to Cpanel::Email::Object email
and send it via SMTP or Sendmail (SMTP is preferred)

=cut

use strict;
use warnings;

use Cpanel::CPAN::IO::Callback::Write ();

use Cpanel::Services::Enabled ();
use Cpanel::Email::Object     ();
use Cpanel::Debug             ();

use Try::Tiny;

my $SMTP_SINGLETON;

our $SENDMAIL_SYSTEM              = '/usr/sbin/sendmail';
our $SMTP_HOST                    = '127.0.0.1';
our $SMTP_MAX_CONNECTION_ATTEMPTS = 1;                      # retry is supported, but send we fallback to sendmail its not currently enabled

=head2 email_message

Send an email message using the params to create
an Cpanel::Email::Object

=head3 Input

C<HASHREF> A hashref that contains the email message that be passed to Cpanel::Email::Object's new function

C<HASHREF> A hashref that contains the transport information will be passed to _email_message_using_smtp and _email_message_using_sendmail

Currently, the following parameters are accepted and only used when the message is sent over SMTP: smtp_user, smtp_pass.

    {
        'smtp_user' => 'bob',
        'smtp_pass' => 'frog',
        ...
    }

=head3 Output

Returns 1 or dies on failures

=cut

sub email_message {
    my ( $opts_ref, $cfg_ref ) = @_;

    if ( !Cpanel::Services::Enabled::is_enabled('exim') ) {
        _email_message_using_sendmail( $opts_ref, $cfg_ref );
        return 1;
    }

    # Try SMTP first, then fallback to sendmail
    try {
        _email_message_using_smtp( $opts_ref, $cfg_ref );
    }
    catch {
        # Fallback to sendmail if the error was anything but a failed
        # recipient.  A failed recipient is not going to be any more successful
        # with sendmail.
        #
        # We already log_warn in _email_message_using_smtp if we get
        # failed recipients so no sense in logging twice.
        #
        my $err = $_;
        if ( !try { $err->isa('Cpanel::Exception::SMTP::FailedRecipient') } ) {
            Cpanel::Debug::log_warn($err);
            _email_message_using_sendmail( $opts_ref, $cfg_ref );
        }
    };
    return 1;
}

#XXX This is invoked directly from tests.
sub _email_message_using_smtp {
    my ( $opts_ref, $cfg_ref ) = @_;

    require Cpanel::SMTP::Singleton;

    my $smtp;

    try {
        $smtp = Cpanel::SMTP::Singleton::localhost( @{$cfg_ref}{ 'smtp_user', 'smtp_pass' } );
        $smtp->mail( $opts_ref->{'from'} );
    }
    catch {
        Cpanel::SMTP::Singleton::close();

        $smtp = Cpanel::SMTP::Singleton::localhost( @{$cfg_ref}{ 'smtp_user', 'smtp_pass' } );
        $smtp->mail( $opts_ref->{'from'} );
    };

    my %good_recipients;
    my $err;
    try {
        %good_recipients = map { $_ => 1 } $smtp->recipient( @{ $opts_ref->{'to'} }, { SkipBad => 1 } );
    }
    catch {
        if ( !try { $_->isa('Cpanel::Exception::SMTP::FailedRecipient') } ) {
            local $@ = $_;
            die;
        }
        $err = $_;
    };

    foreach my $recipient ( @{ $opts_ref->{'to'} } ) {
        if ( !$good_recipients{$recipient} ) {
            Cpanel::Debug::log_warn("The SMTP server “$SMTP_HOST” rejected the recipient “$recipient” while attempting to send a message with the subject “$opts_ref->{'subject'}”");
        }
    }

    if ($err) {
        local $@ = $err;
        die;
    }

    $smtp->data();

    my $email = Cpanel::Email::Object->new($opts_ref);

    my $fh = Cpanel::CPAN::IO::Callback::Write->new(
        sub {
            $smtp->datasend( \@_ );
        }
    );

    $email->print($fh);

    $smtp->flush();
    $smtp->dataend();

    return 1;
}

sub _email_message_using_sendmail {
    my ( $opts_ref, $cfg_ref ) = @_;

    require Cpanel::SafeRun::Object;

    my @args = ( '-odb', '-ti' );
    if ( $cfg_ref->{'smtp_user'} ) {
        push @args, (
            '-oMr',  'esmtpa',
            '-oMa',  '127.0.0.1',
            '-oMaa', 'localhost',
            '-oMt',  $cfg_ref->{'smtp_user'},
            '-oMs',  'localhost',
            '-oMai', $cfg_ref->{'smtp_user'}
        );
    }

    return Cpanel::SafeRun::Object->new_or_die(
        program => scalar _sendmail_bin(),
        args    => \@args,
        stdin   => sub {
            Cpanel::Email::Object->new($opts_ref)->print( shift() );
        },
    );

}

sub _sendmail_bin {
    my $bin = $SENDMAIL_SYSTEM;

    die "$bin is not executable by UID $> ($!)" if !-x $bin;

    return $bin;
}

1;
