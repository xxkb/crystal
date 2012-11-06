require 'spec_helper'

describe 'Type inference: return and mutation' do
  break unless Crystal::CACHE

  test_type = "class Foo; #{rw :value}; end"

  it "types a call with an int" do
    input = parse 'def foo; 1; end; foo'
    mod = infer_type input
    input.last.target_def.return.should eq(mod.int)
  end

  it "types a call with a primitive argument" do
    input = parse 'def foo(x); x; end; foo 1'
    mod = infer_type input
    input.last.target_def.return.should eq(mod.int)
  end

  it "types a call with an object type argument" do
    input = parse 'def foo(x); x; end; foo Object.new'
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1))
  end

  it "types a call returning new type" do
    input = parse 'def foo; Object.new; end; foo'
    mod = infer_type input
    input.last.target_def.return.should eq(mod.object)
  end

  it "types a call not returning path of argument with primitive type" do
    input = parse "#{test_type}; def foo(x); x.value; end; f = Foo.new; f.value = 1; foo(f)"
    mod = infer_type input
    input.last.target_def.return.should eq(mod.int)
  end

  it "types a call returning path of self" do
    input = parse "#{test_type}; f = Foo.new; f.value = Object.new; f.value"
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1, '@value'))
  end

  it "when assining to instance variable, return path of instance variable even if in assign" do
    input = parse "#{test_type}; f = Foo.new; f.value = Object.new"
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1, '@value'))
  end

  it "types a call returning path of argument" do
    input = parse "#{test_type}; def foo(x); x.value; end; f = Foo.new; f.value = Object.new; foo(f)"
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1, '@value'))
  end

  it "types a call returning path of second argument" do
    input = parse "#{test_type}; def foo(y, x); x.value; end; f = Foo.new; f.value = Object.new; foo(0, f)"
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(2, '@value'))
  end

  it "types a call to array getter" do
    input = parse "a = [Object.new]; a[0]"
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1, 'element'))
  end

  it "types a call returning path of self" do
    input = parse %Q(
      #{test_type}
      class Foo
        def foo
          self.value
        end
      end

      x = Foo.new
      x.value = Foo.new
      x.foo)
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1, '@value'))
  end

  it "types a call returning path of self" do
    input = parse %Q(
      #{test_type}
      class Foo
        def foo
          self.value.value
        end
      end

      x = Foo.new
      x.value = Foo.new
      x.value.value = Object.new
      x.foo)
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1, '@value', '@value'))
  end

  it "types a call returning self" do
    input = parse %Q(
      class Foo
        def foo
          self
        end
      end
      Foo.new.foo
    )

    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1))
  end

  it "types a call returning path of argument of second level call" do
    input = parse %Q(
      def foo(x)
        x
      end

      def bar(x)
        foo(x)
      end

      bar(Object.new)
    )
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1))
  end

  it "types a call to object returning path of argument" do
    input = parse %Q(
      class Foo
        def foo(x)
          x
        end
      end
      Foo.new.foo(Object.new)
    )

    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(2))
  end

  it "types a call returning path of self of second level call" do
    input = parse %Q(
      class Foo
        def foo(x)
          x
        end
      end

      def bar(x)
        Foo.new.foo(x)
      end

      bar(Object.new)
    )
    mod = infer_type input
    input.last.target_def.return.should eq(Path.new(1))
  end

  it "cache type mutation" do
    input = parse %Q(
      #{test_type}
      f = Foo.new
      f.value = 1
      )

    mod = infer_type input
    mod.types['Foo'].defs['value='].lookup_instance([ObjectType.new('Foo'), mod.int]).mutations.should eq([Mutation.new(Path.new(1, '@value'), mod.int)])
  end

  it "caches path mutation" do
    input = parse %Q(
      #{test_type}
      class Bar; end
      f = Foo.new
      f.value = Bar.new
      )

    mod = infer_type input
    mod.types['Foo'].defs['value='].lookup_instance([ObjectType.new('Foo'), ObjectType.new('Bar')]).mutations.should eq([Mutation.new(Path.new(1, '@value'), Path.new(2))])
  end

  it "caches long path mutation" do
    input = parse %Q(
      #{test_type}

      def foo(x, y)
        x.value = y.value
      end

      f = Foo.new
      f.value = Object.new

      g = Foo.new
      foo(g, f)
      )

    mod = infer_type input
    mod.defs['foo'].lookup_instance([ObjectType.new('Foo'), ObjectType.new('Foo').with_var('@value', ObjectType.new('Object'))]).
      mutations.should eq([Mutation.new(Path.new(1, '@value'), Path.new(2, '@value'))])
  end

  it "caches nested path mutation" do
    input = parse %Q(
      #{test_type}

      def foo(x)
        x.value.value = 1
      end

      f = Foo.new
      f.value = Foo.new
      foo(f)
      )

    mod = infer_type input
    mod.defs['foo'].lookup_instance([ObjectType.new('Foo').with_var('@value', ObjectType.new('Foo'))]).
      mutations.should eq([Mutation.new(Path.new(1, '@value', '@value'), mod.int)])
  end

  it "caches nested path mutation with another nested path" do
    input = parse %Q(
      #{test_type}

      def foo(x, y)
        x.value.value = y.value
      end

      f = Foo.new
      f.value = Foo.new
      g = Foo.new
      g.value = Object.new
      foo(f, g)
      )

    mod = infer_type input
    foo = ObjectType.new('Foo').with_var('@value', ObjectType.new('Foo'))
    mod.defs['foo'].lookup_instance([foo, ObjectType.new('Foo').with_var('@value', ObjectType.new('Object'))]).
      mutations.should eq([Mutation.new(Path.new(1, '@value', '@value'), Path.new(2, '@value'))])
  end

  it "caches nested path mutation with another nested recursive path" do
    input = parse %Q(
      #{test_type}

      def foo(x, y)
        x.value.value = y.value
      end

      f = Foo.new
      f.value = Foo.new
      g = Foo.new
      g.value = Foo.new
      foo(f, g)
      )

    mod = infer_type input
    foo = ObjectType.new('Foo').with_var('@value', ObjectType.new('Foo'))
    mod.defs['foo'].lookup_instance([foo, foo]).
      mutations.should eq([Mutation.new(Path.new(1, '@value', '@value'), Path.new(2, '@value'))])
  end

  it "computes return to path if assigned to arg" do
    input = parse %Q(
      class Foo
        def value=(value)
          @value = value
        end

        def value
          @value
        end
      end

      def foo(x)
        bar = Foo.new
        x.value = bar
        bar
      end

      f = Foo.new
      b = foo(f)
    )
    mod = infer_type input
    mod.defs['foo'].lookup_instance([ObjectType.new('Foo')]).return.should eq(Path.new(1, '@value'))
  end

  it "computes return type and mutation of it" do
    input = parse %Q(
      #{test_type}
      def foo(x)
        r = Foo.alloc
        r.value = x
        r
      end
      foo(Object.new)
    )
    mod = infer_type input
    input.last.target_def.return.should eq(ObjectType.new('Foo').with_var('@value', ObjectType.new('Object')))
    input.last.target_def.mutations.should eq([Mutation.new(Path.new(0, '@value'), Path.new(1))])
  end

  it "computes return type and nested mutation of it" do
    input = parse %Q(
      #{test_type}
      def foo(x)
        r = Foo.new
        y = Foo.new
        y.value = x
        r.value = y
        r
      end
      foo(Object.new)
    )
    mod = infer_type input
    input.last.target_def.return.should eq(ObjectType.new('Foo').with_var('@value', ObjectType.new('Foo').with_var('@value', ObjectType.new('Object'))))
    input.last.target_def.mutations.should eq([Mutation.new(Path.new(0, '@value', '@value'), Path.new(1))])
  end

  it "computes return type and nested mutation of it (2)" do
    input = parse %Q(
      #{test_type}
      def foo(x)
        r = Foo.new
        r.value = Foo.new
        r.value.value = x
        r
      end
      foo(Object.new)
    )
    mod = infer_type input
    input.last.target_def.return.should eq(ObjectType.new('Foo').with_var('@value', ObjectType.new('Foo').with_var('@value', ObjectType.new('Object'))))
    input.last.target_def.mutations.should eq([Mutation.new(Path.new(0, '@value', '@value'), Path.new(1))])
  end

end
