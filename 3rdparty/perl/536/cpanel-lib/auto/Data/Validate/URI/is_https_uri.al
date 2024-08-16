# NOTE: Derived from blib/lib/Data/Validate/URI.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate::URI;

#line 375 "blib/lib/Data/Validate/URI.pm (autosplit into blib/lib/auto/Data/Validate/URI/is_https_uri.al)"
# -------------------------------------------------------------------------------


sub is_https_uri{
	my $self = shift if ref($_[0]); 
	my $value = shift;
	$self //= shift;
	
	return _test_uri(2, $value, $self);
}

# end of Data::Validate::URI::is_https_uri
1;
