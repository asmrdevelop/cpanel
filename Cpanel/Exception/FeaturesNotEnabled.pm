package Cpanel::Exception::FeaturesNotEnabled;

# cpanel - Cpanel/Exception/FeaturesNotEnabled.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::FeaturesNotEnabled - Exception class when multiple features are disabled

=head1 SYNOPSIS

    use Cpanel::Exception ();

    die Cpanel::Exception::create( 'FeaturesNotEnabled', [ feature_names => [qwfeature1 feature2 feature3] ] );

=head1 DESCRIPTION

Exception class to throw when trying to determine if one or more features are enabled.

=cut

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata parameters:
#   feature_names
#
sub _default_phrase {
    my ($self) = @_;

    my $match = $self->get('match') // 'all';

    return Cpanel::LocaleString->new(
        'You do not have the [numerate,_1,feature,features] [list_and_quoted,_2].',
        scalar @{ $self->get('feature_names') },
        $self->get('feature_names'),
    ) if $match eq 'all';

    return Cpanel::LocaleString->new(
        'You do not have the [numerate,_1,feature,features] [list_or_quoted,_2].',
        scalar @{ $self->get('feature_names') },
        $self->get('feature_names'),
    );
}

1;
