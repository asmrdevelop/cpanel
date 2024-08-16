package Cpanel::Themes::Assets::Base;

# cpanel - Cpanel/Themes/Assets/Base.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

my %attributes_cache;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self       = bless {}, $class;
    my $attributes = $attributes_cache{$class} ||= $self->attributes;

    foreach my $attr ( keys %{$attributes} ) {
        my $attr_hr = $attributes->{$attr};

        # Run the validator
        if ( exists $OPTS{$attr} && exists $attr_hr->{'validator'} ) {
            my $validator = $attr_hr->{'validator'};

            # If the validator is defiend as a regex, then run the regex!
            if ( ref $validator eq 'Regexp' ) {

                # if we don't pass the validator, die!
                if ( $OPTS{$attr} !~ $validator ) {
                    my ( $id_key, $id_val ) = _find_most_human_recognizable_attribute( \%OPTS );
                    die Cpanel::Exception::create(
                        'InvalidParameter',
                        'The configuration entry with “[_1]” of “[_2]” has an invalid value for “[_3]”: “[_4]”.',
                        [ $id_key, $id_val, $attr, $OPTS{$attr} ]
                    );
                }
            }
        }
        elsif ( exists $attributes->{$attr}->{'required'} && $attributes->{$attr}->{'required'} && !exists $OPTS{$attr} ) {
            my ( $id_key, $id_val ) = _find_most_human_recognizable_attribute( \%OPTS );
            die Cpanel::Exception::create( 'MissingParameter', 'The configuration entry with “[_1]” of “[_2]” lacks the required parameter “[_3]”.', [ $id_key, $id_val, $attr ] );
        }

        $self->{$attr} = $OPTS{$attr};
    }

    return $self;
}

#To avoid tracking down which of the many possible configuration entries
#could be missing the relevant value.
sub _find_most_human_recognizable_attribute {
    my $attrs_hr = shift;

    #These are in decreasing order of “helpfulness” in finding the
    #offending entry.
    for my $key (qw( file  name  id  group )) {
        return ( $key, $attrs_hr->{$key} ) if $attrs_hr->{$key};
    }

    return;
}

sub clone {
    my ($self) = @_;

    return bless {%$self}, ref $self;
}

1;
