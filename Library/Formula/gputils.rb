require "formula"

class Gputils < Formula
  homepage "http://gputils.sourceforge.net/"
  url "https://downloads.sourceforge.net/project/gputils/gputils/1.4.0/gputils-1.4.0-1.tar.gz"
  sha1 "26593b7237b0c436b4482d1038216b467ec660b7"

  bottle do
    sha1 "8990a94d132cc92b08518767ecaa25c93246f7cb" => :yosemite
    sha1 "2536c92c27e1982743965fa4c5c3bbae997105e1" => :mavericks
    sha1 "b4ef0c6743be8f8b0cd11e7148cee046f8780d59" => :mountain_lion
  end

  depends_on "flex" => :build if MacOS.version < :snow_leopard

  def install
    system "./configure", "--prefix=#{prefix}", "--disable-dependency-tracking"
    system "make install"
  end

  test do
    # assemble with gpasm
    (testpath/"test.asm").write " movlw 0x42\n end\n"
    system "#{bin}/gpasm -p p16f84 test.asm"
    assert File.exist?("test.hex")

    # disassemble with gpdasm
    output = `#{bin}/gpdasm -p p16f84 test.hex`
    assert_equal "0000:  3042  movlw   0x42\n", output
    assert_equal 0, $?.exitstatus
  end
end
