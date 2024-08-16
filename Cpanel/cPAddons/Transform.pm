
# cpanel - Cpanel/cPAddons/Transform.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Transform;

use strict;
use warnings;

=head1 MODULE

C<Cpanel::cPAddons::Transform>

=head1 DESCRIPTION

C<Cpanel::cPAddons::Transform> provides variable expansion and transformation for
cpaddon based tags of the format: [% prop %] or [% prop | filter %] where prop is a key
in the data passed and filter is a fully qualified function on any namespace.

=head1 FUNCTIONS

=head2 expand(DATA, TEMPLATE)

Expand a [% %] template.

=head3 ARGUMENTS

=over

=item B<DATA> - Hash Ref

Name/value pairs to lookup the substitutions from.

=item B<TEMPLATE> - String

Template for the results with [% %] substitutions.

=back

=head3 RETURNS

String - Fully expanded results

=cut

sub expand {
    my ( $data, $template ) = @_;
    my $out = $template;
    $out =~ s/\[\%\s*([^\s|%\]]*)(\s*\|?\s*([^\s]*?))\s*\%\]/@{[_transform($data, $1, $3 || '')]}/g;
    return $out;
}

# Transform the property into its value with the optional filtering
sub _transform {
    my ( $data, $name, $filter ) = @_;
    my $value = $data->{$name};

    if ($filter) {
        my @parts       = split /::/, $filter;
        my $filter_name = pop @parts;
        my $module      = join '::', @parts;

        eval "require $module";    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        if ( my $exception = $@ ) {
            warn "Filter module $module is not available, skipping: $exception";
        }
        else {
            if ( my $fn = $module->can($filter_name) ) {
                $value = $fn->($value);
            }
            else {
                warn "Filter function $filter_name not defined in $module, skipping.";
            }
        }
    }
    return $value;
}

1;
