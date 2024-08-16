package Cpanel::iContact::EventImportance::Writer;

# cpanel - Cpanel/iContact/EventImportance/Writer.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw( Cpanel::iContact::EventImportance );

use Cpanel::Exception ();

#NOTE: The significances of these are irrelevant to this module,
#but they are posted here as a guide to keep implementors consistent.
my @ALLOWED_IMPORTANCES = (
    0,    #means not to send a notice for the given event
    1,    #most important
    2,
    3,    #least important
);

use Cpanel::Transaction::File::JSON ();    # PPI USE OK -- used in new via __TRANSACTION_CLASS

sub new {
    my ( $class, @args ) = @_;

    my $self = $class->SUPER::new(@args);

    #If this transaction is on a new datastore, then we need to set the
    #transaction's data pointer to this object's data.
    if ( 'SCALAR' eq ref $self->{'_trans'}->get_data() ) {
        $self->{'_trans'}->set_data( $self->{'_data'} );
    }

    return $self;
}

sub __TRANSACTION_CLASS {
    return 'Cpanel::Transaction::File::JSON';
}

sub save_and_close {
    my ( $self, @args ) = @_;

    $self->_die_if_done();

    my ( $ok, $err ) = $self->{'_trans'}->save_and_close(@args);
    die Cpanel::Exception->create_raw($err) if !$ok;

    $self->{'_done'} = 1;

    return 1;
}

#NOTE: There are two "opposite" methods to this in the reader object!
#(i.e., one that falls back, and the other that doesn't)
#
sub set_event_importance {
    my ( $self, $app, $event, $importance ) = @_;

    $self->_die_if_done();

    $self->_verify_app($app);
    $self->_verify_event($event);

    return $self->_set_event_importance( $app, $event, $importance );
}

sub set_application_importance {
    my ( $self, $app, $importance ) = @_;

    $self->_die_if_done();

    $self->_verify_app($app);

    return $self->_set_event_importance( $app, '*', $importance );
}

sub unset_application_importance {
    my ( $self, $app ) = @_;

    $self->_die_if_done();

    if ( $self->{'_data'}{$app} ) {
        delete $self->{'_data'}{$app}{'*'};

        $self->_remove_app_if_empty($app);
    }

    return 1;
}

sub unset_event_importance {
    my ( $self, $app, $event ) = @_;

    $self->_die_if_done();

    if ( $self->{'_data'}{$app} && exists $self->{'_data'}{$app}{$event} ) {
        delete $self->{'_data'}{$app}{$event};

        $self->_remove_app_if_empty($app);
    }

    return 1;
}

sub _remove_app_if_empty {
    my ( $self, $app ) = @_;

    if ( !%{ $self->{'_data'}{$app} } ) {
        delete $self->{'_data'}{$app};
    }

    return 1;
}

sub _set_event_importance {
    my ( $self, $app, $event, $importance ) = @_;

    $self->_verify_importance($importance);

    $self->{'_data'}{$app}{$event} = $importance;

    return 1;
}

sub _verify_importance {
    my ( $self, $importance ) = @_;

    if ( !grep { $_ eq $importance } @ALLOWED_IMPORTANCES ) {
        die "invalid importance: “$importance” (must be one of: @ALLOWED_IMPORTANCES)";
    }

    return 1;
}

sub _verify_app {
    my ( $self, $app ) = @_;

    #This has to accommodate "legacy" names.
    die "Invalid application: “$app”" if $app !~ m<\A[a-zA-Z][a-zA-Z_.]*\z>;

    return 1;
}

sub _verify_event {
    my ( $self, $event ) = @_;

    die "Invalid event: “$event”" if $event !~ m<\A[A-Za-z_][A-Za-z0-9_]*\z>;

    return 1;
}

sub _die_if_done {
    my ($self) = @_;

    return 1 if !$self->{'_done'};

    die Cpanel::Exception->create_raw('This object’s transaction was already saved and closed.');
}

1;
