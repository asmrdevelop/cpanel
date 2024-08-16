# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 239 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_numeric.al)"
# -------------------------------------------------------------------------------


sub is_numeric{
	my $self = shift if ref($_[0]);
	my $value = shift;
	
	return unless defined($value);
	
	return unless looks_like_number($value);
	
	# looks like it really is a number.  Untaint it and return
	($value) = $value =~ /([\d\.\-+e]+)/;
	
	return $value  + 0;
}

# end of Data::Validate::is_numeric
1;
