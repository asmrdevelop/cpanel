package Cpanel::SysPkgs::APT::Preferences::ExcludePackages;

# cpanel - Cpanel/SysPkgs/APT/Preferences/ExcludePackages.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::SysPkgs::APT::Preferences';

=head1 NAME

Cpanel::SysPkgs::APT::Preferences::ExcludePackages

=head1 DESCRIPTION

Provide an object to interact with the content from

     /etc/apt/preferences.d/99-cpanel-exclude-packages

That file contains the list of packages we want to block updates
or do not install on Ubuntu servers.

=head1 SYNOPSIS

    use Cpanel::SysPkgs::APT::Preferences::ExcludePackages ();

    my $excludes = Cpanel::SysPkgs::APT::Preferences::ExcludePackages->new;

    $excludes->add( 'my-package' );
    $excludes->add( 'some-packages-like-*' );

    $excludes->has_rule_for_package( 'my-package' );
    $excludes->has_rule_for_package( 'some-packages-like-this' );

    $excludes->remove( 'my-package' );

=cut

=head1 METHODS

=head2 $self->name()

Provide the name of the apt preferences use to read/save custom cPanel exclude rules.

=cut

sub name ($self) {
    return q[99-cpanel-exclude-packages];
}

=head2 $self->add( $rule )

Add and save a rule for package or pattern provided by '$rule'.

=cut

sub add ( $self, $rule ) {

    my $data = $self->content();

    return 1 if $data->{$rule};    # rule already set

    $data->{$rule} = {
        'Pin'          => 'release *',
        'Pin-Priority' => -1,
    };

    return $self->write;
}

=head2 $self->remove( $rule )

Remove and save a rule for package or pattern provided by '$rule'.

=cut

sub remove ( $self, $rule ) {

    my $data = $self->content();

    return unless defined $data->{$rule};

    delete $data->{$rule};

    return $self->write;
}

=head2 $self->has_rule_for_package( $rule )

Check if the package or rule '$rule' is already blocked.

=cut

sub has_rule_for_package ( $self, $rule ) {

    my $data = $self->content();

    return 1 if defined $data->{$rule};

    return 0 if $rule =~ qr[\*];

    # perform a RegExp search
    foreach my $k ( sort keys $data->%* ) {
        next unless $k =~ qr{\*};
        my $re = $k;
        $re =~ s{\*}{.*};

        return 1 if $rule =~ $re;
    }

    return 0;
}

1;
