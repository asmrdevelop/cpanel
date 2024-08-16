package Cpanel::Quota::Temp::Object;

# cpanel - Cpanel/Quota/Temp/Object.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# A mixin class for operations that require quota to be lifted
# This is currently only used for Cpanel::Email::Convert::User

use strict;
use Cpanel::Exception   ();
use Cpanel::Quota::Temp ();

sub lift_user_quota {
    my ($self) = @_;

    foreach my $required (qw(system_user original_pid verbose)) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $required ] ) if !length $self->{$required};
    }

    print "Temporarily lifting quota restrictions for “$self->{'system_user'}”.\n" if $self->{'verbose'};
    $self->{'cpanel_quota_temp'} = Cpanel::Quota::Temp->new( user => $self->{'system_user'} );
    $self->{'cpanel_quota_temp'}->disable();

    return;
}

sub restore_user_quota {
    my ($self) = @_;

    return if !$self->{'cpanel_quota_temp'};

    print "Restoring quota restrictions for “$self->{'system_user'}”.\n" if $self->{'verbose'};
    $self->{'cpanel_quota_temp'}->restore();
    return;
}

sub DESTROY {
    my ($self) = @_;

    if ( $self->{'original_pid'} == $$ ) {
        $self->restore_user_quota();
    }

    return 1;
}

1;
