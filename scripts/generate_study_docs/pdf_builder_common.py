import os
import sys
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether, HRFlowable
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY

# --- COLOR PALETTE ---
PRIMARY = colors.HexColor('#0D47A1')       # Deep Royal Navy
SECONDARY = colors.HexColor('#00695C')     # Deep Teal
ACCENT = colors.HexColor('#C62828')        # Deep Crimson
AMBER = colors.HexColor('#E65100')         # Deep Amber
DARK_TEXT = colors.HexColor('#212121')     # Charcoal
MUTED_TEXT = colors.HexColor('#546E7A')    # Slate Gray
LIGHT_BG = colors.HexColor('#F8FAFC')      # Crisp Off-White
CARD_BG = colors.HexColor('#FFFFFF')       # Pure White
CODE_BG = colors.HexColor('#1E293B')       # Modern Slate-Dark
CODE_TEXT = colors.HexColor('#38BDF8')     # Sky Blue
BORDER_COLOR = colors.HexColor('#CBD5E1')  # Cool Gray Border
LINE_BG_ALT = colors.HexColor('#F1F5F9')   # Subtle alternating row

class VisionMateNumberedCanvas(canvas.Canvas):
    """
    Two-pass canvas to dynamically compute and stamp running headers,
    footers, and total page count ('Page X of Y').
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            if self._pageNumber > 1: # Suppress headers on cover page
                self.draw_header_footer(num_pages)
            canvas.Canvas.showPage(self)
        canvas.Canvas.save(self)

    def draw_header_footer(self, page_count):
        self.saveState()
        
        # --- Running Header ---
        self.setFont('Helvetica-Bold', 8)
        self.setFillColor(PRIMARY)
        self.drawString(45, 11 * 72 - 36, "VISIONMATE: TECHNICAL ARCHITECTURE & CODE STUDY")
        
        self.setFont('Helvetica', 8)
        self.setFillColor(MUTED_TEXT)
        doc_title = getattr(self, 'doc_running_title', 'Feature Technical Specification')
        self.drawRightString(8.5 * 72 - 45, 11 * 72 - 36, doc_title)
        
        # Header Accent Rule
        self.setStrokeColor(BORDER_COLOR)
        self.setLineWidth(0.75)
        self.line(45, 11 * 72 - 42, 8.5 * 72 - 45, 11 * 72 - 42)
        
        # --- Running Footer ---
        self.setStrokeColor(BORDER_COLOR)
        self.setLineWidth(0.75)
        self.line(45, 42, 8.5 * 72 - 45, 42)
        
        self.setFont('Helvetica', 8)
        self.setFillColor(MUTED_TEXT)
        self.drawString(45, 30, "Confidential / Academic & Engineering Research Project Documentation")
        
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.setFont('Helvetica-Bold', 8)
        self.setFillColor(PRIMARY)
        self.drawRightString(8.5 * 72 - 45, 30, page_str)
        
        self.restoreState()


def get_visionmate_styles():
    """Returns a curated typography system for high-density technical reading."""
    base_styles = getSampleStyleSheet()
    styles = {}

    styles['DocTitle'] = ParagraphStyle(
        'DocTitle',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=24,
        leading=30,
        textColor=PRIMARY,
        alignment=TA_LEFT,
        spaceAfter=8
    )

    styles['DocSubtitle'] = ParagraphStyle(
        'DocSubtitle',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=12,
        leading=16,
        textColor=MUTED_TEXT,
        alignment=TA_LEFT,
        spaceAfter=15
    )

    styles['SectionHeading'] = ParagraphStyle(
        'SectionHeading',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=14,
        leading=18,
        textColor=PRIMARY,
        spaceBefore=14,
        spaceAfter=6,
        keepWithNext=True
    )

    styles['SubSectionHeading'] = ParagraphStyle(
        'SubSectionHeading',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11,
        leading=15,
        textColor=SECONDARY,
        spaceBefore=10,
        spaceAfter=4,
        keepWithNext=True
    )

    styles['SubSubSectionHeading'] = ParagraphStyle(
        'SubSubSectionHeading',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9.5,
        leading=13,
        textColor=DARK_TEXT,
        spaceBefore=7,
        spaceAfter=3,
        keepWithNext=True
    )

    styles['Body'] = ParagraphStyle(
        'Body',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=12,
        textColor=DARK_TEXT,
        alignment=TA_JUSTIFY,
        spaceAfter=5
    )

    styles['BodyBold'] = ParagraphStyle(
        'BodyBold',
        parent=styles['Body'],
        fontName='Helvetica-Bold'
    )

    styles['BulletItem'] = ParagraphStyle(
        'BulletItem',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=11.5,
        textColor=DARK_TEXT,
        leftIndent=12,
        firstLineIndent=-8,
        spaceAfter=3
    )

    styles['CodeInline'] = ParagraphStyle(
        'CodeInline',
        parent=base_styles['Normal'],
        fontName='Courier-Bold',
        fontSize=8,
        leading=10,
        textColor=PRIMARY
    )

    styles['CodeLine'] = ParagraphStyle(
        'CodeLine',
        parent=base_styles['Normal'],
        fontName='Courier',
        fontSize=7.2,
        leading=9.2,
        textColor=colors.HexColor('#0F172A')
    )

    styles['CodeExplanation'] = ParagraphStyle(
        'CodeExplanation',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=7.8,
        leading=10.5,
        textColor=DARK_TEXT
    )

    styles['TableHeader'] = ParagraphStyle(
        'TableHeader',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8,
        leading=10,
        textColor=colors.white,
        alignment=TA_LEFT
    )

    styles['TableCell'] = ParagraphStyle(
        'TableCell',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=7.8,
        leading=10.2,
        textColor=DARK_TEXT,
        alignment=TA_LEFT
    )

    styles['TableCellBold'] = ParagraphStyle(
        'TableCellBold',
        parent=styles['TableCell'],
        fontName='Helvetica-Bold',
        textColor=PRIMARY
    )

    styles['CalloutText'] = ParagraphStyle(
        'CalloutText',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=8.2,
        leading=11.5,
        textColor=DARK_TEXT
    )

    styles['MetaKey'] = ParagraphStyle(
        'MetaKey',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11,
        textColor=SECONDARY
    )

    styles['MetaVal'] = ParagraphStyle(
        'MetaVal',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=11,
        textColor=DARK_TEXT
    )

    styles['CardHeader'] = ParagraphStyle(
        'CardHeader',
        parent=base_styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11,
        textColor=colors.white,
        alignment=TA_LEFT
    )

    styles['CardCode'] = ParagraphStyle(
        'CardCode',
        parent=base_styles['Normal'],
        fontName='Courier',
        fontSize=7.2,
        leading=9.8,
        textColor=colors.HexColor('#F8FAFC'),
        alignment=TA_LEFT
    )

    styles['CardExplanation'] = ParagraphStyle(
        'CardExplanation',
        parent=base_styles['Normal'],
        fontName='Helvetica',
        fontSize=8.2,
        leading=11.5,
        textColor=DARK_TEXT,
        alignment=TA_LEFT
    )

    return styles


def create_cover_banner(title_text, subtitle_text, doc_ref, styles):
    """Creates a sleek, modern header block for the top of the document."""
    elements = []
    
    # Category tag
    tag_p = Paragraph(f"<b>DOCUMENT REF: {doc_ref}</b> &nbsp;|&nbsp; <b>MULTIMODAL ASSISTIVE PLATFORM FOR VISUALLY IMPAIRED</b>", 
                      ParagraphStyle('Tag', fontName='Helvetica-Bold', fontSize=8, leading=10, textColor=SECONDARY))
    elements.append(tag_p)
    elements.append(Spacer(1, 4))
    
    # Title
    title_p = Paragraph(title_text, styles['DocTitle'])
    elements.append(title_p)
    
    # Subtitle
    sub_p = Paragraph(subtitle_text, styles['DocSubtitle'])
    elements.append(sub_p)
    
    # Decorative rule
    elements.append(HRFlowable(width="100%", thickness=2, color=PRIMARY, spaceBefore=2, spaceAfter=10))
    return elements


def create_metadata_box(metadata_items, styles):
    """Creates a two-column clean metadata table."""
    data = []
    keys = list(metadata_items.keys())
    for i in range(0, len(keys), 2):
        row = []
        k1 = keys[i]
        v1 = metadata_items[k1]
        row.extend([Paragraph(k1, styles['MetaKey']), Paragraph(str(v1), styles['MetaVal'])])
        
        if i + 1 < len(keys):
            k2 = keys[i+1]
            v2 = metadata_items[k2]
            row.extend([Paragraph(k2, styles['MetaKey']), Paragraph(str(v2), styles['MetaVal'])])
        else:
            row.extend(["", ""])
        data.append(row)
        
    t = Table(data, colWidths=[1.3 * inch, 2.3 * inch, 1.3 * inch, 2.3 * inch])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), LIGHT_BG),
        ('BOX', (0,0), (-1,-1), 1, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ]))
    return t


def create_callout(heading, text, alert_type='info', styles=None):
    """Renders a highlighted box for key engineering takeaways or warnings."""
    bg_color = LIGHT_BG
    border_c = PRIMARY
    title_color = PRIMARY
    
    if alert_type == 'warning':
        bg_color = colors.HexColor('#FFFBEB')
        border_c = AMBER
        title_color = AMBER
    elif alert_type == 'danger':
        bg_color = colors.HexColor('#FEF2F2')
        border_c = ACCENT
        title_color = ACCENT
    elif alert_type == 'success':
        bg_color = colors.HexColor('#F0FDF4')
        border_c = SECONDARY
        title_color = SECONDARY

    content = [
        Paragraph(f"<b>{heading}</b>", ParagraphStyle('CalloutHead', fontName='Helvetica-Bold', fontSize=8.5, leading=11, textColor=title_color)),
        Spacer(1, 2),
        Paragraph(text, styles['CalloutText'])
    ]
    
    t = Table([[content]], colWidths=[7.2 * inch])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), bg_color),
        ('BOX', (0,0), (-1,-1), 1.2, border_c),
        ('TOPPADDING', (0,0), (-1,-1), 5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 5),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('RIGHTPADDING', (0,0), (-1,-1), 8),
    ]))
    return t


def create_table(headers, rows, col_widths, styles):
    """Creates a beautifully styled data table."""
    table_data = []
    # Header row
    table_data.append([Paragraph(h, styles['TableHeader']) for h in headers])
    
    # Body rows
    for r in rows:
        formatted_row = []
        for cell in r:
            if isinstance(cell, str):
                formatted_row.append(Paragraph(cell, styles['TableCell']))
            else:
                formatted_row.append(cell)
        table_data.append(formatted_row)
        
    t = Table(table_data, colWidths=col_widths, repeatRows=1)
    
    t_style = [
        ('BACKGROUND', (0, 0), (-1, 0), PRIMARY),
        ('ALIGN', (0, 0), (-1, 0), 'LEFT'),
        ('TOPPADDING', (0, 0), (-1, -1), 3.5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3.5),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ('BOX', (0, 0), (-1, -1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
    ]
    
    # Alternating row colors
    for i in range(1, len(table_data)):
        if i % 2 == 0:
            t_style.append(('BACKGROUND', (0, i), (-1, i), LINE_BG_ALT))
        else:
            t_style.append(('BACKGROUND', (0, i), (-1, i), colors.white))
            
    t.setStyle(TableStyle(t_style))
    return t


def create_line_by_line_table(items, styles):
    """
    Renders the core Line-by-Line Code Explanation & Rationale.
    items: list of tuples: (line_range_or_num, code_snippet, rationale_and_reason)
    """
    table_data = [
        [
            Paragraph("Line #", styles['TableHeader']),
            Paragraph("Source Code Snippet", styles['TableHeader']),
            Paragraph("Algorithmic Function & Technical Rationale", styles['TableHeader'])
        ]
    ]
    
    for line_num, code_txt, rationale_txt in items:
        # Wrap code text into courier
        code_p = Paragraph(f"<font face='Courier' color='#0F172A'>{code_txt}</font>", styles['CodeLine'])
        rat_p = Paragraph(rationale_txt, styles['CodeExplanation'])
        num_p = Paragraph(f"<b>{line_num}</b>", styles['TableCellBold'])
        table_data.append([num_p, code_p, rat_p])
        
    t = Table(table_data, colWidths=[0.65 * inch, 3.15 * inch, 3.4 * inch], repeatRows=1)
    
    t_style = [
        ('BACKGROUND', (0, 0), (-1, 0), SECONDARY),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
        ('LEFTPADDING', (0, 0), (-1, -1), 4),
        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOX', (0, 0), (-1, -1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
    ]
    
    for i in range(1, len(table_data)):
        if i % 2 == 0:
            t_style.append(('BACKGROUND', (0, i), (-1, i), LINE_BG_ALT))
        else:
            t_style.append(('BACKGROUND', (0, i), (-1, i), colors.white))
            
    t.setStyle(TableStyle(t_style))
    return t


def create_code_card(file_name, line_range, code_snippet, what_it_does, why_needed, styles):
    """
    Renders an elegant, full-width Code Card for Deep Dive documentation.
    - Header: File path and line numbers on dark navy banner.
    - Code Window: High-contrast dark IDE styling with formatted courier code.
    - Explanation: Clear, plain-English summary of what the code does and why it was built.
    """
    # 1. Header paragraph
    header_html = f"<b>FILE:</b> <font color='#38BDF8'>{file_name}</font> &nbsp;&nbsp;|&nbsp;&nbsp; <b>LINES:</b> <font color='#FACC15'>{line_range}</font>"
    header_p = Paragraph(header_html, styles['CardHeader'])

    # 2. Code HTML formatting
    formatted_code_lines = []
    for raw_line in code_snippet.strip().split('\n'):
        l_stripped = raw_line.lstrip(' ')
        leading_spaces = len(raw_line) - len(l_stripped)
        indent_html = '&nbsp;' * (leading_spaces * 2)
        safe_line = l_stripped.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        formatted_code_lines.append(f"{indent_html}{safe_line}")
    code_html = "<br/>".join(formatted_code_lines)
    code_p = Paragraph(code_html, styles['CardCode'])

    # 3. Plain English explanation paragraphs
    expl_items = [
        Paragraph(f"<b>What this code does:</b> {what_it_does}", styles['CardExplanation']),
        Spacer(1, 4),
        Paragraph(f"<b>Why we need it:</b> {why_needed}", styles['CardExplanation'])
    ]

    card_table = Table(
        [
            [header_p],
            [code_p],
            [expl_items]
        ],
        colWidths=[7.2 * inch]
    )

    card_table.setStyle(TableStyle([
        # Header Row
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0F172A')),
        ('TOPPADDING', (0, 0), (-1, 0), 4),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 4),
        ('LEFTPADDING', (0, 0), (-1, 0), 8),
        ('RIGHTPADDING', (0, 0), (-1, 0), 8),

        # Code Window Row
        ('BACKGROUND', (0, 1), (-1, 1), colors.HexColor('#1E293B')),
        ('TOPPADDING', (0, 1), (-1, 1), 6),
        ('BOTTOMPADDING', (0, 1), (-1, 1), 6),
        ('LEFTPADDING', (0, 1), (-1, 1), 10),
        ('RIGHTPADDING', (0, 1), (-1, 1), 10),

        # Explanation Box Row
        ('BACKGROUND', (0, 2), (-1, 2), colors.HexColor('#F8FAFC')),
        ('TOPPADDING', (0, 2), (-1, 2), 6),
        ('BOTTOMPADDING', (0, 2), (-1, 2), 6),
        ('LEFTPADDING', (0, 2), (-1, 2), 10),
        ('RIGHTPADDING', (0, 2), (-1, 2), 10),

        # Outer border
        ('BOX', (0, 0), (-1, -1), 1.2, colors.HexColor('#CBD5E1')),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#E2E8F0')),
    ]))

    return card_table
