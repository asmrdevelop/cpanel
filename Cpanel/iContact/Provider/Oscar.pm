package Cpanel::iContact::Provider::Oscar;

# cpanel - Cpanel/iContact/Provider/Oscar.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Hostname        ();
use Cpanel::LoadModule      ();
use Cpanel::SafeRun::Object ();
use Cpanel::Exception       ();

use parent 'Cpanel::iContact::Provider::IM';

###########################################################################
#
# Method:
#   send
#
# Description:
#   This implements sending OSCAR (ICQ) messages.  For arguments to create
#   a Cpanel::iContact::Provider::Oscar object, see Cpanel::iContact::Provider.
#
# Exceptions:
#   This module throws on failure
#
# Returns: 1
#
sub send {
    my ($self) = @_;

    my $args_hr          = $self->{'args'};
    my $contactshash_ref = $self->{'contact'};

    my ( $im_subject, $im_msg ) = $self->get_im_subject_and_message();

    foreach my $recipient ( @{ $args_hr->{'to'} } ) {
        $self->sendim(
            'user'      => $contactshash_ref->{'user'},
            'password'  => $contactshash_ref->{'password'},
            'recipient' => $recipient,
            'message'   => $im_subject . "\n\n" . $im_msg
        );
    }

    return 1;
}

sub sendim {
    my ( $self, %OPTS ) = @_;

    foreach my $required (qw(user password recipient message)) {
        if ( !$OPTS{$required} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] );
        }
    }

    $OPTS{'type'} = 'icq';

    my $hostname = Cpanel::Hostname::gethostname();
    if ( $OPTS{'message'} !~ /\Q$hostname\E/ ) {
        substr( $OPTS{'message'}, 0, 0, qq{[$hostname] \n} );
    }

    if ( $ENV{'CPANEL_DEBUG_LEVEL'} && $ENV{'CPANEL_DEBUG_LEVEL'} >= 1 ) {
        print STDERR __PACKAGE__ . ":sendim from $OPTS{'user'} to $OPTS{'recipient'} [$OPTS{'message'}]\n";
    }

    return _do_send_im( \%OPTS );
}

sub _do_send_im {
    my ($opts_ref) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Serializer');

    my $run = Cpanel::SafeRun::Object->new(
        program => _sendim_bin(),
        stdin   => \Cpanel::AdminBin::Serializer::Dump($opts_ref),
    );

    if ( $run->CHILD_ERROR() ) {
        die $run->stderr() . $run->autopsy();
    }

    return 1;
}

# For mocking in tests
sub _sendim_bin {
    return '/usr/local/cpanel/bin/icontact_sendim';
}

1;
