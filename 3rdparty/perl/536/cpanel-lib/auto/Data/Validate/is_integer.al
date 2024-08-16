# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 162 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_integer.al)"
# -------------------------------------------------------------------------------


sub is_integer{
	my $self = shift if ref($_[0]); 
	my $value = shift;
	
	return unless defined($value);
	return unless defined(is_numeric($value)); # for efficiency
	
	# see if we can parse it to an number without loss
	my($int, $leftover) = POSIX::strtod($value);
	
	return if $leftover;
	
	# we're having issues testing very large integers.  Math::BigInt
	# can do this for us, but defeats the purpose of being
	# lightweight. So, we're going to try a huristic method to choose
	# how to test for integernesss
	if(!$Config{uselongdouble} && length($int) > 10){
		my $i = Math::BigInt->new($value);
		return unless $i->is_int();
		
		# untaint
		($int) = $i->bstr() =~ /(.+)/;
		return $int;
	}
		
	 
	# shorter integer must be identical to the raw cast
	return unless (($int + 0) == ($value + 0));
	
	# could still be a float at this point.
	return if $value =~ /[^0-9\-]/;
	
	# looks like it really is an integer.  Untaint it and return
	($value) = $int =~ /([\d\-]+)/;
	
	return $value + 0;
}

# end of Data::Validate::is_integer
1;
