# Ebook Generation Process - Sequence Diagrams

This document illustrates the ebook generation workflow using Mermaid sequence diagrams.

## 1. Overall Ebook Build Process

```mermaid
sequenceDiagram
    participant User
    participant npm as npm<br/>run ebook:build
    participant invoke as invoke-build.ps1<br/>(project)
    participant skill as shared-copilot-skills/<br/>ebook-build
    participant output as ebook-output/

    User->>npm: Trigger build
    npm->>invoke: PowerShell execution
    invoke->>invoke: Resolve config files
    invoke->>invoke: Read build.json metadata
    invoke->>skill: Call invoke-ebook-build.ps1

    activate skill
    skill->>skill: Stage docs/ and config
    skill->>skill: Validate cover image exists
    skill->>skill: Process Mermaid diagrams
    skill->>skill: Merge Markdown chapters
    skill->>skill: Call convert-to-kindle.ps1

    activate skill
    skill->>skill: Build TOC from chapter structure
    skill->>skill: Normalize page breaks
    skill->>skill: Generate manuscript.md
    deactivate skill

    skill->>skill: Call render-html-to-pdf.cjs
    activate skill
    skill->>skill: Render HTML to PDF via Chromium
    skill->>output: Save cover.pdf
    skill->>output: Save ebook.pdf
    deactivate skill

    skill->>skill: Call generate-kdp-package.ps1
    activate skill
    skill->>output: Save kdp-registration.md
    deactivate skill

    skill->>output: Save manuscript.md
    skill->>output: Save cover images (jpg, png)
    deactivate skill

    skill-->>invoke: Complete
    invoke-->>npm: Exit success
    npm-->>User: Build complete

    output-->>User: EPUB, PDF, Markdown, KDP metadata
```

## 2. Cover Image Handling Pipeline

```mermaid
sequenceDiagram
    participant Config as Metadata/Build<br/>Configuration
    participant Validate as Input<br/>Validation
    participant Copy as File<br/>Copy/Stage
    participant Embed as Ebook<br/>Embedding
    participant Output as Output<br/>Formats

    Config->>Validate: Provide cover path
    Validate->>Validate: Check file exists
    Validate->>Validate: Verify format (JPG/PNG)
    Validate->>Validate: Check dimensions
    
    alt Valid Cover
        Validate->>Copy: File path confirmed
        Copy->>Copy: Stage cover to temp
        Copy->>Embed: Cover ready
        
        Embed->>Embed: EPUB: Add to package manifest
        Embed->>Embed: PDF: Embed as first page
        Embed->>Embed: KDP: Reference for upload
        
        Embed->>Output: ebook.epub (cover + chapters)
        Embed->>Output: ebook.pdf (cover page + manuscript)
        Embed->>Output: kdp-registration.md (cover reference)
    else Invalid Cover
        Validate->>Output: Error: Skip cover embedding
        Output-->>Output: Warn: No cover in output
    end
```

## 3. Markdown Chapter Discovery and Merging

```mermaid
sequenceDiagram
    participant Disk as docs/<br/>file system
    participant Scanner as Chapter<br/>Scanner
    participant Parser as Markdown<br/>Parser
    participant Merger as Chapter<br/>Merger
    participant Output as Output<br/>Manuscript

    Scanner->>Disk: Discover chapters (01-*, 02-*, ...)
    Disk-->>Scanner: Chapter directories list
    
    loop For Each Chapter Dir
        Scanner->>Parser: Read chapter files
        Parser->>Parser: Parse frontmatter
        Parser->>Parser: Extract heading hierarchy
        Parser->>Parser: Process Mermaid blocks
        Parser-->>Merger: Chapter content + metadata
    end

    Merger->>Merger: Sort by chapter number
    Merger->>Merger: Insert page breaks
    Merger->>Merger: Build table of contents
    Merger->>Merger: Normalize heading levels
    Merger->>Output: Write merged manuscript.md

    Output-->>Output: manuscript.md (all chapters + TOC)
```

## 4. KDP Registration Package Generation

```mermaid
sequenceDiagram
    participant Manuscript as Merged<br/>Manuscript
    participant Metadata as KDP<br/>Metadata
    participant Generator as KDP<br/>Generator
    participant Template as Registration<br/>Template
    participant Output as KDP<br/>Package

    Manuscript->>Generator: Provide merged content
    Metadata->>Generator: Provide KDP-specific metadata
    
    Generator->>Generator: Extract title/subtitle/author
    Generator->>Generator: Extract keywords and categories
    Generator->>Generator: Extract pricing info
    Generator->>Template: Populate template fields

    Template->>Generator: Registration form structure
    Generator->>Generator: Format content for KDP upload
    Generator->>Generator: Include ISBNs/identifiers
    Generator->>Generator: Add copyright/rights info
    Generator->>Generator: Reference cover image path

    Generator->>Output: kdp-registration.md
    Output-->>Output: Ready for KDP dashboard
```

## 5. Configuration Flow

```mermaid
sequenceDiagram
    participant Project as Project<br/>Directory
    participant BuildConfig as build.json
    participant Metadata as metadata.yaml
    participant Invoke as invoke-build.ps1
    participant Skill as Shared Skill<br/>Scripts

    Project->>BuildConfig: Project config
    Project->>Metadata: Project metadata
    
    Invoke->>Invoke: Resolve repo root
    Invoke->>BuildConfig: Load build.json
    Invoke->>Metadata: Load metadata.yaml
    
    BuildConfig->>Invoke: Provide sourceRoot, coverFile, formats
    Metadata->>Invoke: Provide title, subtitle, author, cover path
    
    Invoke->>Invoke: Merge configs
    Invoke->>Invoke: Validate required fields
    Invoke->>Invoke: Resolve relative paths to absolute
    
    Invoke->>Skill: Pass unified config object
    Skill->>Skill: Use config for all processing
    Skill->>Project: Generate outputs based on config
```

## 6. Error Handling and Validation

```mermaid
sequenceDiagram
    participant Build as Build Process
    participant Validate as Validation<br/>Step
    participant Check1 as Check: Config<br/>Files Exist
    participant Check2 as Check: Source<br/>Files Readable
    participant Check3 as Check: Cover<br/>Image Valid
    participant Error as Error<br/>Handler
    participant Output as Output<br/>or Fail

    Build->>Validate: Start validation
    
    Validate->>Check1: Verify build.json, metadata.yaml
    alt Config Missing
        Check1->>Error: Error: Config not found
        Error->>Output: Fail with message
    else Config Valid
        Check1->>Validate: Proceeed
    end
    
    Validate->>Check2: Verify docs/ accessible
    alt Source Unreadable
        Check2->>Error: Error: Permission denied
        Error->>Output: Fail with message
    else Source Valid
        Check2->>Validate: Proceed
    end
    
    Validate->>Check3: Verify cover file exists & valid
    alt Cover Missing
        Check3->>Error: Warning: Cover not found
        Error->>Output: Proceed without cover
    else Cover Invalid Format
        Check3->>Error: Warning: Unsupported format
        Error->>Output: Attempt format conversion
    else Cover Valid
        Check3->>Validate: Proceed
    end
    
    Validate->>Output: Validation complete
    Output-->>Output: Proceed to build or fail gracefully
```

---

## Configuration Reference

### build.json Fields
- `projectName`: Project identifier
- `sourceRoot`: Location of chapter Markdown files
- `outputDir`: Output directory for generated files
- `coverFile`: Path to cover image file
- `metadataFile`: Path to metadata.yaml
- `formats`: Array of output formats (epub, pdf, kdp-markdown)

### metadata.yaml Fields
- `title`: Book title
- `subtitle`: Book subtitle
- `creator`: Author name
- `cover`: Path to cover image file
- `language`: Language code (e.g., ja-JP)
- `description`: Book description
- `rights`: Copyright/license text

---

**Last Updated**: 2026-04-12  
**Diagrams Version**: 1.0
