package Cpanel::Template::Plugin::MagicRevision;

# cpanel - Cpanel/Template/Plugin/MagicRevision.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';
use Cpanel::MagicRevision ();

sub new {
    my ($class) = @_;
    return Cpanel::MagicRevisionObj->new($class);
}

package Cpanel::MagicRevisionObj;

sub new {
    my $self = {};
    bless $self;
    return $self;
}

sub calculate_magic_url {
    my $self = shift;
    goto &Cpanel::MagicRevision::calculate_magic_url;
}

1;
