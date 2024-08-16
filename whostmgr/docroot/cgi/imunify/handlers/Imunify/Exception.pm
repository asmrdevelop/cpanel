package Imunify::Exception;

use strict;
use warnings FATAL => 'all';

use Cpanel::JSON;
use Imunify::Render;

sub new {
    my $class = shift;
    my $self = {
        'message' => shift || undef
    };

    return bless $self, $class;
}

sub getMessage() {
    my ($self) = @_;
    return $self->{'message'};
}

sub asJSON() {
    my ($self) = @_;
    my %error = (
        'messages' => [$self->getMessage()],
        'result' => 'error',
    );

    Imunify::Render::JSONHeader(Imunify::Render->HTTP_STATUS_OK);
    print Cpanel::JSON::SafeDump(\%error);
    exit 1;
}

1;