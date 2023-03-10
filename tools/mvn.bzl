def mvn(name, pom="pom.xml", srcs=[], deps=[], visibility = None):

    PACKAGE_NAME = native.package_name().replace("/","_")
    DEP_LOCATIONS = ["$(locations %s)" % d for d in deps] + ["$(locations @src_maven_tree//:%s_deps)" % PACKAGE_NAME]

    native.filegroup(
        name = "mvn_srcs",
        srcs = srcs,
    )

    # Run mvn install for each of the dependency packages
    # This doesn't recompile anything, instead just taking the pom and the target
    # dir and installing the package to the local maven repo.
    # This is important to ensure that the correct versions of the package deps
    # are present in the local maven repo before compilation.
    native.genrule(
        name = "%s-install-deps" % name,
        srcs = [
            "@src_maven_tree//:%s_deps" % PACKAGE_NAME
        ] + deps,
        outs = ["install.completed"],
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
        local = True,
        cmd = """
            # Set the java for repeatability - see toolchains
            export JAVA_HOME=$$PWD/$(JAVABASE)
            BUILD_ROOT=$$PWD
            OUTPUT_MARKER=$$BUILD_ROOT/$@
            DEP_LOCATIONS="%s"

            for file in $$DEP_LOCATIONS
            do
                if [[ $$file == *.tar ]]
                then
                    cd $$(mktemp -d)
                    tar -xf $$BUILD_ROOT/$$file
                    mvn -B -q -N validate jar:jar install:install
                fi
            done

            touch $$OUTPUT_MARKER
        """ % " ".join(DEP_LOCATIONS),
        message = "Unpacking deps: %s" % native.package_name(),
        visibility = ["//visibility:public"],
    )

    native.genrule(
        name = name,
        srcs = [
            pom,
            ":mvn_srcs",
            ":%s-install-deps" % name,
        ] + deps,
        outs = ["%s.tar" % name],
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
        local = True,
        cmd = """
            # Set the java for repeatability - see toolchains
            export JAVA_HOME=$$PWD/$(JAVABASE)
            BUILD_ROOT=$$PWD
            OUTPUT_TAR=$$BUILD_ROOT/$@

            # Change into the directory with the pom
            PROJECT_DIR=$$PWD/$$(dirname $(location :pom.xml))
            cd $$PROJECT_DIR
            mkdir -p target/

            # Skip tests and skip compiling tests
            # Batch mode, quiet mode, non-recursive mode
            mvn -B -q -N install -DskipTests

            tar -czf $$OUTPUT_TAR target/ pom.xml >/dev/null
        """,
        message = "Building: %s" % native.package_name(),
        visibility = ["//visibility:public"],
    )

    native.alias(
        name = "mvn",
        actual = ":%s" % name,
    )

def mvn_test(name, pom="pom.xml", srcs=[], deps=[], visibility = None):

    PACKAGE_NAME = native.package_name().replace("/","_")
    DEP_LOCATIONS = ["$(locations %s)" % d for d in deps] + ["$(locations @src_maven_tree//:%s_deps)" % PACKAGE_NAME]

    native.filegroup(
        name = "mvn_test_srcs",
        srcs = srcs,
    )

    native.genrule(
        name = name,
        srcs = [
            "pom.xml",
        ] + deps,
        outs = ["junit.xml"],
        toolchains = ["@bazel_tools//tools/jdk:current_java_runtime"],
        local = True,
        cmd = """
            # Set the java for repeatability - see toolchains
            export JAVA_HOME=$$PWD/$(JAVABASE)
            BUILD_ROOT=$$PWD
            OUTPUT=$$BUILD_ROOT/$@

            #npm install -g junit-merge

            # Change into the directory with the pom
            PROJECT_DIR=$$PWD/$$(dirname $(location :pom.xml))
            cd $$PROJECT_DIR
            mvn -B -q -N test || true

            mkdir -p target/surefire-reports/
            touch target/surefire-reports/empty.xml
            junit-merge -o $$OUTPUT -d target/surefire-reports/
        """
    )