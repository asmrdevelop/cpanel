package Cpanel::LinkedNode::Convert::Common::Mail::Backend;

# cpanel - Cpanel/LinkedNode/Convert/Common/Mail/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Mail::Backend

=head1 SYNOPSIS

    my $mail_domains_ar = get_mail_domains_for_step( \%input );

=head1 DESCRIPTION

This module contains logic that’s useful in both to-distributed
and from-distributed mail conversions.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::WildcardDomain::Tiny   ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $domains_ar = get_mail_domains_for_step(\%INPUT)

Determines a user’s mail-capable domains and returns a reference
to an (unsorted) array of those domains.

%INPUT must contain C<username>.

=cut

sub get_mail_domains_for_step ($input_hr) {
    my $cpuser_obj = Cpanel::Config::LoadCpUserFile::load_or_die( $input_hr->{'username'} );

    my @mail_domains = grep { !Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @{ $cpuser_obj->domains_ar() };

    return \@mail_domains;
}

1;
