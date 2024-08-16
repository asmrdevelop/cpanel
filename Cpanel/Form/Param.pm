package Cpanel::Form::Param;

# cpanel - Cpanel/Form/Param.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Form ();

our $VERSION = 0.2;

my $_last_call;

sub new {
    my ( $class, $args_ref ) = @_;
    my $self = bless {}, $class;

    if ( ref $args_ref->{'parseform_hr'} eq 'HASH' ) {
        $self->_init_from_parseform_hr( $args_ref->{'parseform_hr'} );
    }
    else {
        if ( ref $_last_call eq 'Cpanel::Form::Param' ) {
            return $_last_call;
        }
        else {
            $self->_init_from_parseform_hr( scalar Cpanel::Form::parseform() );
        }
    }

    $_last_call = $self;

    return $self;
}

sub _init_from_parseform_hr {
    my ( $self, $parseform_hr ) = @_;

    # make parseform()'s key' => 'v1' , 'key-0' => 'v2', 'key-1' => 'v3' into 'key' => [v1, v2, v3]

    for my $key ( sort { ( $a =~ m{-(\d+)\z} ? int $1 : -1 ) <=> ( $b =~ m{-(\d+)\z} ? int $1 : -1 ) } keys %{$parseform_hr} ) {
        my $value = $parseform_hr->{$key};
        $key =~ s{-\d+$}{};
        push @{ $self->{$key} }, $value;
    }

    return;
}

sub param {
    my ( $self, $name, @args ) = @_;

    if (@args) {
        $self->{$name} = [@args];    # not \@args
    }

    if ( !defined $name ) {
        return wantarray ? keys %{$self} : [ keys %{$self} ];
    }
    return if !exists $self->{$name};
    return if ref $self->{$name} ne 'ARRAY';

    return wantarray ? @{ $self->{$name} } : $self->{$name}->[0];
}

1;

__END__

=head1 CGI->param() behavior with Cpanel::Form

my $prm => Cpanel::Form::Param->new();

or

my $prm => Cpanel::Form::Param->new({
    'parseform_hr' => \%same_type_of_hash_that_parseform_returns,
});

Works like CGI[::Simple and friends]->param Getopt::Param->param etc

PARAM_NAME:
for my $name ( $prm->param() ) { # no args returns list
       print "Starting $param\n";
       my $first = $prm->param($name); # w/ name in scalar context = first value
       print "\tFirst $name is $first\n";

       PARAM_VALUE:
       for my $value ( $prm->param($name) ) { # w/ name in array context = all values
           print "\t\t$value\n";
       }
}
