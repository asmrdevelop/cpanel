
# cpanel - Whostmgr/ModSecurity/Vendor/Provided.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Vendor::Provided;

use strict;
use Whostmgr::ModSecurity::Vendor ();

sub provided_vendors {
    return [
        Whostmgr::ModSecurity::Vendor->new(
            vendor_id      => 'OWASP3',
            name           => 'OWASP ModSecurity Core Rule Set V3.0',
            description    => 'SpiderLabs OWASP V3 curated ModSecurity rule set',
            installed_from => 'http://httpupdate.cpanel.net/modsecurity-rules/meta_OWASP3.yaml',
            vendor_url     => 'https://go.cpanel.net/modsecurityowasp',
        )
    ];
}

1;

__END__

=head1 Whostmgr::ModSecurity::Vendor::Provided

This module provides only one method, provided_vendors, which adds cPanel-provided
ModSecurity rulesets to the UI in WHM's Home > Security Center > ModSecurity Vendors.

Additional array elements may be added, and should be in the form of a Whostmgr::ModSecurity::Vendor
object, created using that module's new() method, with the following attributes:

=over

=item B<vendor_id>

A short code, which is used as a unique identifyer for the ruleset. Not displayed, but used as
a directory name in the backend.

=item B<name>

A human-readable name, displayed as the name of the set for the user.

=item B<description>

A text description of the rule set.

=item B<installed_from>

The URL which points at a metadata YAML for the set--which will, in turn, describe where to get
the actual set, when it was last tested, and other matters

=item B<vendor_url>

A URL which points at vendor--or cPanel--documentation about the set

=back

=cut
